package com.bank.digital_banking.module.auth.merchant;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.common.util.*;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.security.JwtTokenProvider;
import com.bank.digital_banking.module.auth.service.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;
import java.time.OffsetDateTime;
import java.util.*;
import static com.bank.digital_banking.module.auth.merchant.MerchantAuthDtos.*;

/** Attempt mutations serialize on an advisory key before owner -> attempt -> session locks. */
@Service @RequiredArgsConstructor
public class MerchantAuthService {
    private final JdbcTemplate jdbc;
    private final UserRepository users;
    private final AuthSessionRepository sessions;
    private final SessionService sessionService;
    private final AppPinService pins;
    private final DeviceService devices;
    private final JwtTokenProvider tokens;
    private final MerchantAuthConfig config;
    private final AuditTrail audit;
    private final ObjectMapper json;
    private final TransactionLockPolicy locks;

    private record Attempt(UUID id, String client, String redirect, String state, String challenge,
                           String secretHash, String handoffHash, String installation, String device,
                           String status, OffsetDateTime expires, Long owner, UUID approvingSession,
                           String codeHash, String exchangeHash, UUID session, String receipt,
                           OffsetDateTime receiptExpires) {}
    private Attempt find(UUID id, boolean lock) {
        return jdbc.query("SELECT * FROM merchant_auth_attempts WHERE id=?" + (lock ? " FOR UPDATE" : ""), (r,i) ->
                new Attempt(id,r.getString("client_id"),r.getString("redirect_uri"),r.getString("state"),r.getString("challenge"),
                    r.getString("secret_hash"),r.getString("handoff_hash"),r.getString("installation_hash"),r.getString("device_name"),
                    r.getString("status"),r.getObject("expires_at",OffsetDateTime.class),r.getObject("approved_by",Long.class),
                    r.getObject("approved_session_id",UUID.class),r.getString("code_hash"),r.getString("exchange_hash"),
                    r.getObject("session_id",UUID.class),r.getString("recovery_ciphertext"),
                    r.getObject("recovery_expires_at",OffsetDateTime.class)), id).stream().findFirst().orElseThrow(this::invalid);
    }
    private User owner(long id) { return users.findLockedById(id).orElseThrow(this::invalid); }
    private void serialize(UUID id) {
        jdbc.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?, 827131))",id.toString());
    }
    private void customer(User user, UUID sid) {
        var session = sessions.findLockedById(sid).orElseThrow(this::invalid);
        sessionService.requirePurpose(session,"CUSTOMER");
        valid(session);
        if (!session.getUser().getId().equals(user.getId()) || !user.isProfileComplete()
                || user.getRoles().stream().noneMatch(r -> r.getName()==ERole.ROLE_CUSTOMER)) throw invalid();
        if (sessionService.isPinLocked(sid)) throw new AppPinService.PinRejected("PIN_REQUIRED", "Unlock the Customer App first");
    }
    private void valid(AuthSession session) {
        if (session.getRevokedAt()!=null || !session.getExpiresAt().isAfter(OffsetDateTime.now())
                || !session.getUser().isEnabled() || !session.getUser().isProfileComplete()
                || session.getUser().getRoles().stream().noneMatch(r -> r.getName()==ERole.ROLE_CUSTOMER)
                || session.getDevice().getStatus()!=DeviceStatus.ACTIVE)
            throw new AuthenticationFailedException("SESSION_INVALID","Session is expired or revoked");
    }
    private void secret(Attempt a, String raw) { if (!MerchantAuthCrypto.matches(a.secretHash(),raw)) throw invalid(); }
    private void handoff(Attempt a, String raw) { if (!MerchantAuthCrypto.matches(a.handoffHash(),raw)) throw invalid(); }
    private void pending(Attempt a) {
        if (!a.expires().isAfter(OffsetDateTime.now())) throw problem("MERCHANT_AUTH_EXPIRED");
        if (!a.status().equals("PENDING")) throw problem(error(a.status()));
    }
    private String error(String status) {
        return switch(status) {
            case "DENIED" -> "MERCHANT_AUTH_DENIED";
            case "CANCELLED" -> "MERCHANT_AUTH_CANCELLED";
            case "EXPIRED" -> "MERCHANT_AUTH_EXPIRED";
            default -> "MERCHANT_AUTH_USED";
        };
    }
    private ApiException invalid() { return new ApiException(HttpStatus.BAD_REQUEST,"MERCHANT_AUTH_INVALID","Merchant sign-in credentials are invalid"); }
    private ApiException problem(String code) { return new ApiException(HttpStatus.CONFLICT,code,"This Merchant sign-in request is no longer available"); }

    @Transactional
    public Started start(Start request) {
        config.requireClient(request.clientId(),request.redirectUri()); locks.apply();
        UUID id=UUID.randomUUID(); String handoff=MerchantAuthCrypto.random();
        OffsetDateTime expires=OffsetDateTime.now().plusSeconds(120);
        jdbc.update("""
            INSERT INTO merchant_auth_attempts(id,client_id,redirect_uri,state,challenge,secret_hash,handoff_hash,
                installation_hash,device_name,expires_at) VALUES (?,?,?,?,?,?,?,?,?,?)
            """,id,request.clientId(),request.redirectUri(),request.state(),request.codeChallenge(),request.attemptSecretHash(),
                HashUtils.sha256(handoff),HashUtils.sha256(request.installationId()),request.deviceName().strip(),expires);
        audit.success("MERCHANT_AUTH","STARTED",id.toString());
        return new Started(id,expires,config.approval+"?attemptId="+id+"&handoffToken="+handoff,"com.bank.customer_app");
    }

    @Transactional
    public Details details(User user, UUID sid, UUID id, String raw) {
        config.requireEnabled(); locks.apply(); serialize(id); user=owner(user.getId());
        Attempt a=find(id,true); handoff(a,raw); customer(user,sid); pending(a);
        return new Details(id,MerchantAuthConfig.NAME,a.device(),a.status(),a.expires(),MerchantAuthConfig.PACKAGE);
    }
    @Transactional(noRollbackFor=AppPinService.PinRejected.class)
    public Callback approve(User user, UUID sid, UUID id, Approve request) {
        config.requireEnabled(); locks.apply(); serialize(id); user=owner(user.getId());
        Attempt a=find(id,true); handoff(a,request.handoffToken()); pending(a); customer(user,sid);
        pins.verifyForMerchantApproval(user,sid,request.pin());
        String code=MerchantAuthCrypto.random();
        jdbc.update("UPDATE merchant_auth_attempts SET status='APPROVED',approved_by=?,approved_session_id=?,code_hash=? WHERE id=?",
                user.getId(),sid,HashUtils.sha256(code),id);
        audit.successAs(user,"MERCHANT_AUTH","APPROVED",id.toString());
        return new Callback(a.redirect()+"?code="+code+"&state="+a.state(),MerchantAuthConfig.PACKAGE);
    }
    @Transactional
    public Callback deny(User user, UUID sid, UUID id, Handoff request) {
        config.requireEnabled(); locks.apply(); serialize(id); user=owner(user.getId());
        Attempt a=find(id,true); handoff(a,request.handoffToken()); pending(a); customer(user,sid);
        jdbc.update("UPDATE merchant_auth_attempts SET status='DENIED' WHERE id=?",id);
        audit.successAs(user,"MERCHANT_AUTH","DENIED",id.toString());
        return new Callback(a.redirect()+"?error=access_denied&state="+a.state(),MerchantAuthConfig.PACKAGE);
    }

    @Transactional
    public Status status(UUID id, Secret request) {
        config.requireEnabled(); locks.apply(); Attempt a=find(id,true); secret(a,request.attemptSecret());
        if (Set.of("PENDING","APPROVED").contains(a.status()) && !a.expires().isAfter(OffsetDateTime.now())) {
            jdbc.update("UPDATE merchant_auth_attempts SET status='EXPIRED',recovery_ciphertext=NULL WHERE id=?",id);
            return new Status(id,"EXPIRED",a.expires());
        }
        return new Status(id,a.status(),a.expires());
    }

    @Transactional
    public Status cancel(UUID id, Secret request) {
        config.requireEnabled(); locks.apply(); serialize(id);
        Attempt before=find(id,false); secret(before,request.attemptSecret());
        if (before.owner()!=null) owner(before.owner());
        Attempt a=find(id,true); secret(a,request.attemptSecret());
        if (a.session()!=null) sessionService.logout(a.session());
        if (!Set.of("DENIED","EXPIRED").contains(a.status())) {
            jdbc.update("UPDATE merchant_auth_attempts SET status='CANCELLED',recovery_ciphertext=NULL,recovery_expires_at=NULL WHERE id=?",id);
            audit.success("MERCHANT_AUTH","CANCELLED",id.toString());
            return new Status(id,"CANCELLED",a.expires());
        }
        return new Status(id,a.status(),a.expires());
    }

    @Transactional
    public TokenResponseDto exchange(Exchange request, String ip) {
        config.requireClient(request.clientId(),request.redirectUri()); locks.apply(); serialize(request.attemptId());
        Attempt before=find(request.attemptId(),false); secret(before,request.attemptSecret());
        if (before.owner()==null) throw problem(error(before.status()));
        User user=owner(before.owner()); Attempt a=find(request.attemptId(),true);
        secret(a,request.attemptSecret());
        if (!a.client().equals(request.clientId()) || !a.redirect().equals(request.redirectUri())
                || !MerchantAuthCrypto.matches(HashUtils.sha256(a.state()),request.state())
                || !MerchantAuthCrypto.matches(a.codeHash(),request.code())
                || !MerchantAuthCrypto.matches(HashUtils.sha256(a.challenge()),MerchantAuthCrypto.challenge(request.codeVerifier()))) throw invalid();
        if (a.status().equals("CONSUMED")) {
            if (!MerchantAuthCrypto.matches(a.exchangeHash(),request.exchangeKey()) || a.receipt()==null
                    || a.receiptExpires()==null || !a.receiptExpires().isAfter(OffsetDateTime.now())) throw problem("MERCHANT_AUTH_USED");
            var session=sessions.findLockedById(a.session()).orElseThrow(this::invalid);
            valid(session); sessionService.requirePurpose(session,"MERCHANT");
            TokenResponseDto recovered;
            try { recovered=json.readValue(MerchantAuthCrypto.open(config.recoveryKey,a.id(),a.receipt()),TokenResponseDto.class); }
            catch (IllegalStateException ex) { throw problem("MERCHANT_AUTH_USED"); }
            // Rotation invalidates a response-loss receipt. It must never resurrect
            // old refresh credentials or revoke the newly rotated session by reuse.
            if (!MerchantAuthCrypto.matches(session.getRefreshTokenHash(),recovered.getRefreshToken())) throw problem("MERCHANT_AUTH_USED");
            return recovered;
        }
        if (!a.status().equals("APPROVED")) throw problem(error(a.status()));
        if (!a.expires().isAfter(OffsetDateTime.now())) throw problem("MERCHANT_AUTH_EXPIRED");
        customer(user,a.approvingSession());
        Device device=devices.bind(user,"merchant:"+MerchantAuthConfig.CLIENT+":"+a.installation(),a.device(),"MOBILE","Android",ip);
        TokenResponseDto response=sessionService.createMerchant(user,device);
        jdbc.update("""
            UPDATE merchant_auth_attempts SET status='CONSUMED',exchange_hash=?,session_id=?,
              recovery_ciphertext=?,recovery_expires_at=? WHERE id=?
            """,HashUtils.sha256(request.exchangeKey()),response.getSessionId(),
                MerchantAuthCrypto.seal(config.recoveryKey,a.id(),json.writeValueAsString(response)),OffsetDateTime.now().plusSeconds(60),a.id());
        audit.successAs(user,"MERCHANT_AUTH","EXCHANGED",a.id().toString());
        return response;
    }

    @Transactional(noRollbackFor=AuthenticationFailedException.class)
    public TokenResponseDto refresh(Refresh request) {
        config.requireEnabled(); locks.apply();
        var claims=tokens.parse(request.refreshToken(),"refresh"); owner(Long.parseLong(claims.getSubject()));
        TokenResponseDto response=sessionService.refreshMerchant(request.refreshToken());
        jdbc.update("UPDATE merchant_auth_attempts SET recovery_ciphertext=NULL,recovery_expires_at=NULL WHERE session_id=?",response.getSessionId());
        return response;
    }

    private AuthSession merchant(User user, UUID sid) {
        config.requireEnabled(); locks.apply(); owner(user.getId());
        var session=sessions.findLockedById(sid).orElseThrow(this::invalid);
        valid(session); sessionService.requirePurpose(session,"MERCHANT");
        if (!session.getUser().getId().equals(user.getId())) throw invalid();
        return session;
    }
    @Transactional
    public Identity identity(User user, UUID sid) {
        merchant(user,sid);
        var shops=jdbc.query("SELECT merchant_id,store_name,status::text FROM merchants WHERE owner_user_id=? ORDER BY id LIMIT 2",
                (r,i)->new Shop(r.getString(1),r.getString(2),r.getString(3)),user.getId());
        String state=shops.isEmpty()?"SHOP_REQUIRED":shops.size()>1?"RECOVERY_REQUIRED":
                shops.getFirst().status().equals("ACTIVE")?"READY":"RESTRICTED";
        return new Identity(sid,user.getId(),MerchantAuthConfig.CLIENT,state,shops.size()==1?shops.getFirst():null);
    }
    @Transactional
    public void logout(User user, UUID sid) {
        merchant(user,sid); sessionService.logout(sid);
        jdbc.update("UPDATE merchant_auth_attempts SET recovery_ciphertext=NULL,recovery_expires_at=NULL WHERE session_id=?",sid);
    }
    @Transactional
    public List<SessionInfo> list(User user, UUID customerSid) {
        locks.apply(); user=owner(user.getId()); customer(user,customerSid);
        return jdbc.query("""
            SELECT s.id,d.device_name,s.created_at,s.expires_at FROM auth_sessions s JOIN devices d ON d.id=s.device_id
            WHERE s.user_id=? AND s.purpose='MERCHANT' AND s.revoked_at IS NULL AND s.expires_at>CURRENT_TIMESTAMP
            ORDER BY s.created_at DESC LIMIT 100
            """,(r,i)->new SessionInfo(r.getObject(1,UUID.class),MerchantAuthConfig.NAME,r.getString(2),
                r.getObject(3,OffsetDateTime.class),r.getObject(4,OffsetDateTime.class)),user.getId());
    }
    @Transactional
    public void revoke(User user, UUID customerSid, UUID merchantSid) {
        locks.apply(); user=owner(user.getId()); customer(user,customerSid);
        var target=sessions.findLockedById(merchantSid).orElseThrow(this::invalid);
        if (!target.getUser().getId().equals(user.getId()) || !target.getPurpose().equals("MERCHANT")) throw invalid();
        sessionService.logout(merchantSid);
        jdbc.update("UPDATE merchant_auth_attempts SET recovery_ciphertext=NULL,recovery_expires_at=NULL WHERE session_id=?",merchantSid);
        audit.successAs(user,"MERCHANT_AUTH","REVOKED",merchantSid.toString());
    }
}
