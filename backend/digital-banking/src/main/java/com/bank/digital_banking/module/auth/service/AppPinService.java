package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.*;

@Service @RequiredArgsConstructor
public class AppPinService {
    private final JdbcTemplate jdbc;
    private final UserRepository users;
    private final AuthSessionRepository sessions;
    private final SessionService sessionService;
    private final ContinuationPersistence continuation;
    private final PasswordEncoder encoder;
    private final AuditTrail audit;
    @Value("${app.pin.pepper:${app.jwt.secret}}") private String pepper;
    private static final SecureRandom RANDOM = new SecureRandom();

    public record Challenge(String ticket, Long userId, boolean configured, int attemptsRemaining,
                            boolean recoveryRequired, boolean canRecover, String displayName) {}
    private record Pin(String hash, int failures) {}
    private record Ticket(AuthSession session, boolean canRecover) {}
    public static class PinRejected extends ApiException {
        public PinRejected(String code, String message) { super(HttpStatus.FORBIDDEN, code, message); }
    }
    private ApiException invalidTicket() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "PIN_TICKET_INVALID", "Sign in again to continue");
    }
    private AuthSession valid(AuthSession session) {
        sessionService.requirePurpose(session, "CUSTOMER");
        if (session.getRevokedAt() != null || !session.getExpiresAt().isAfter(OffsetDateTime.now())
                || !session.getUser().isEnabled() || session.getDevice().getStatus() != DeviceStatus.ACTIVE) throw invalidTicket();
        continuation.requireCustomer(session.getUser());
        return session;
    }
    private Pin pin(long userId) {
        return jdbc.query("SELECT pin_hash, failed_attempts FROM customer_app_pins WHERE user_id = ?",
                (row, index) -> new Pin(row.getString(1), row.getInt(2)), userId).stream().findFirst().orElse(null);
    }
    private Challenge challenge(String raw, AuthSession session, boolean recovery) {
        Pin pin = pin(session.getUser().getId());
        String name = String.join(" ", Objects.toString(session.getUser().getFirstName(), ""),
                Objects.toString(session.getUser().getLastName(), "")).strip();
        return new Challenge(raw, session.getUser().getId(), pin != null, pin == null ? 5 : 5 - pin.failures(),
                pin != null && pin.failures() >= 5, recovery && session.getCreatedAt().isAfter(OffsetDateTime.now().minusMinutes(10)),
                name.isBlank() ? session.getUser().getUsername() : name);
    }
    private Ticket ticket(String raw) {
        var ids = jdbc.query("SELECT s.user_id, l.session_id FROM app_pin_locks l JOIN auth_sessions s ON s.id=l.session_id WHERE l.ticket_hash=?",
                (row, index) -> Map.entry(row.getLong(1), row.getObject(2, UUID.class)), HashUtils.sha256(raw));
        if (ids.isEmpty()) throw invalidTicket();
        var id = ids.getFirst();
        users.findLockedById(id.getKey()).orElseThrow(this::invalidTicket);
        AuthSession session = valid(sessions.findLockedById(id.getValue()).orElseThrow(this::invalidTicket));
        var recovery = jdbc.query("SELECT recovery_allowed FROM app_pin_locks WHERE session_id=? AND ticket_hash=?",
                (row, index) -> row.getBoolean(1), session.getId(), HashUtils.sha256(raw));
        if (recovery.isEmpty()) throw invalidTicket();
        if (AuditTrail.request() != null) AuditTrail.request().setAttribute(AuditTrail.ACTOR, id.getKey().toString());
        return new Ticket(session, recovery.getFirst());
    }

    @Transactional
    public Challenge prepare(User user, UUID sessionId) {
        continuation.requireCustomer(user);
        if (!user.isProfileComplete()) throw new ApiException(HttpStatus.FORBIDDEN, "PROFILE_INCOMPLETE", "Complete your profile first");
        users.findLockedById(user.getId()).orElseThrow(this::invalidTicket);
        AuthSession session = valid(sessions.findLockedById(sessionId).orElseThrow(this::invalidTicket));
        if (!session.getUser().getId().equals(user.getId())) throw invalidTicket();
        byte[] random = new byte[32]; RANDOM.nextBytes(random);
        String raw = Base64.getUrlEncoder().withoutPadding().encodeToString(random);
        jdbc.update("""
            INSERT INTO app_pin_locks(session_id,ticket_hash,locked,recovery_allowed) VALUES (?,?,TRUE,TRUE)
            ON CONFLICT(session_id) DO UPDATE SET ticket_hash=EXCLUDED.ticket_hash, locked=TRUE
            """, sessionId, HashUtils.sha256(raw));
        boolean recovery = jdbc.queryForObject("SELECT recovery_allowed FROM app_pin_locks WHERE session_id=?", Boolean.class, sessionId);
        Challenge state = challenge(raw, session, recovery);
        if (!state.configured() && !state.canRecover()) throw new ApiException(HttpStatus.FORBIDDEN,
                "PIN_RECOVERY_AUTH_REQUIRED", "Verify your identity again before creating a PIN");
        audit.successAs(user, "AUTH", "PIN_GATE_PREPARED", sessionId.toString());
        return state;
    }
    @Transactional
    public Challenge lock(String raw) {
        Ticket ticket = ticket(raw);
        jdbc.update("UPDATE app_pin_locks SET locked=TRUE WHERE session_id=?", ticket.session().getId());
        Challenge state = challenge(raw, ticket.session(), ticket.canRecover());
        if (!state.configured() && !state.canRecover()) throw invalidTicket();
        return state;
    }
    @Transactional
    public TokenResponseDto setup(String raw, String pin, String confirm, boolean reset) {
        if (!pin.matches("[0-9]{4}") || !pin.equals(confirm))
            throw new ApiException(HttpStatus.BAD_REQUEST, "PIN_CONFIRMATION_MISMATCH", "Enter the same four digits twice");
        Ticket ticket = ticket(raw);
        AuthSession session = ticket.session();
        if (!session.getUser().isProfileComplete()) throw new ApiException(HttpStatus.FORBIDDEN, "PROFILE_INCOMPLETE", "Complete your profile first");
        Pin existing = pin(session.getUser().getId());
        if (!ticket.canRecover() || !session.getCreatedAt().isAfter(OffsetDateTime.now().minusMinutes(10)))
            throw new ApiException(HttpStatus.FORBIDDEN, "PIN_RECOVERY_AUTH_REQUIRED", "Verify your identity again before creating or resetting a PIN");
        if (existing != null && (!reset || !ticket.canRecover()
                || !session.getCreatedAt().isAfter(OffsetDateTime.now().minusMinutes(10))))
            throw new ApiException(HttpStatus.FORBIDDEN, "PIN_RECOVERY_AUTH_REQUIRED", "Verify your email or Telegram again before resetting your PIN");
        jdbc.update("""
            INSERT INTO customer_app_pins(user_id,pin_hash) VALUES (?,?)
            ON CONFLICT(user_id) DO UPDATE SET pin_hash=EXCLUDED.pin_hash,failed_attempts=0,updated_at=CURRENT_TIMESTAMP
            """, session.getUser().getId(), encoder.encode(secret(session.getUser().getId(), pin)));
        if (existing != null) {
            jdbc.update("UPDATE auth_sessions SET revoked_at=CURRENT_TIMESTAMP WHERE user_id=? AND id<>? AND revoked_at IS NULL",
                    session.getUser().getId(), session.getId());
            invalidateMerchantApprovals(session.getUser().getId());
        }
        audit.successAs(session.getUser(), "AUTH", existing == null ? "PIN_CREATED" : "PIN_RESET", session.getId().toString());
        return unlockSession(session);
    }
    @Transactional(noRollbackFor = PinRejected.class)
    public TokenResponseDto unlock(String raw, String pin) {
        Ticket ticket = ticket(raw);
        AuthSession session = ticket.session();
        jdbc.update("UPDATE app_pin_locks SET locked=TRUE WHERE session_id=?", session.getId());
        Pin saved = pin(session.getUser().getId());
        if (saved == null) throw new PinRejected("PIN_SETUP_REQUIRED", "Create your PIN first");
        if (saved.failures() >= 5) throw new PinRejected("PIN_RECOVERY_REQUIRED", "Too many attempts. Verify your identity to reset your PIN");
        if (!encoder.matches(secret(session.getUser().getId(), pin), saved.hash())) {
            int failures = saved.failures() + 1;
            jdbc.update("UPDATE customer_app_pins SET failed_attempts=? WHERE user_id=?", failures, session.getUser().getId());
            throw new PinRejected(failures >= 5 ? "PIN_RECOVERY_REQUIRED" : "PIN_INVALID", "The PIN did not match");
        }
        jdbc.update("UPDATE customer_app_pins SET failed_attempts=0 WHERE user_id=?", session.getUser().getId());
        audit.successAs(session.getUser(), "AUTH", "PIN_UNLOCKED", session.getId().toString());
        return unlockSession(session);
    }
    private TokenResponseDto unlockSession(AuthSession session) {
        jdbc.update("UPDATE app_pin_locks SET locked=FALSE,recovery_allowed=FALSE,pin_generation=pin_generation+1 WHERE session_id=?", session.getId());
        return sessionService.issueAfterPin(session);
    }
    @Transactional(noRollbackFor = PinRejected.class)
    public void change(User user, UUID sessionId, String current, String replacement, String confirm) {
        continuation.requireCustomer(user);
        users.findLockedById(user.getId()).orElseThrow(this::invalidTicket);
        AuthSession session = valid(sessions.findLockedById(sessionId).orElseThrow(this::invalidTicket));
        if (!session.getUser().getId().equals(user.getId()) || sessionService.isPinLocked(sessionId))
            throw new PinRejected("PIN_REQUIRED", "Unlock the app before changing your PIN");
        if (!replacement.matches("[0-9]{4}") || !replacement.equals(confirm))
            throw new ApiException(HttpStatus.BAD_REQUEST, "PIN_CONFIRMATION_MISMATCH", "Enter the same four digits twice");
        Pin saved = pin(user.getId());
        if (saved == null) throw new PinRejected("PIN_SETUP_REQUIRED", "Create your PIN first");
        if (saved.failures() >= 5) throw new PinRejected("PIN_RECOVERY_REQUIRED", "Verify your identity to reset your PIN");
        if (!encoder.matches(secret(user.getId(), current), saved.hash())) {
            int failures = saved.failures() + 1;
            jdbc.update("UPDATE customer_app_pins SET failed_attempts=? WHERE user_id=?", failures, user.getId());
            if (failures >= 5) jdbc.update("UPDATE app_pin_locks SET locked=TRUE WHERE session_id IN (SELECT id FROM auth_sessions WHERE user_id=?)", user.getId());
            throw new PinRejected(failures >= 5 ? "PIN_RECOVERY_REQUIRED" : "PIN_INVALID", "The current PIN did not match");
        }
        if (current.equals(replacement)) throw new ApiException(HttpStatus.BAD_REQUEST, "PIN_UNCHANGED", "Choose a different PIN");
        jdbc.update("UPDATE customer_app_pins SET pin_hash=?,failed_attempts=0,updated_at=CURRENT_TIMESTAMP WHERE user_id=?",
                encoder.encode(secret(user.getId(), replacement)), user.getId());
        jdbc.update("UPDATE auth_sessions SET revoked_at=CURRENT_TIMESTAMP WHERE user_id=? AND id<>? AND revoked_at IS NULL", user.getId(), sessionId);
        invalidateMerchantApprovals(user.getId());
        audit.successAs(user, "AUTH", "PIN_CHANGED", sessionId.toString());
    }
    private void invalidateMerchantApprovals(long userId) {
        jdbc.update("""
            UPDATE merchant_auth_attempts SET status=CASE WHEN status='APPROVED' THEN 'CANCELLED' ELSE status END,
                recovery_ciphertext=NULL,recovery_expires_at=NULL WHERE approved_by=?
            """,userId);
    }
    public record TransferProof(String proof, int expiresInSeconds) {}
    public static final int TRANSFER_PROOF_SECONDS = 120;

    /** A distinct approval purpose: verifies fresh digits without minting a transfer proof. */
    @Transactional(noRollbackFor = PinRejected.class)
    public void verifyForMerchantApproval(User user, UUID sessionId, String pin) {
        verifyFresh(user, sessionId, pin, "Unlock the Customer App before approving sign-in", "The PIN did not match");
    }

    /** Fresh digits for one Merchant owner transfer; shares the persistent five-attempt budget. */
    @Transactional(noRollbackFor = PinRejected.class)
    public void verifyForOwnerTransfer(User user, UUID sessionId, String pin) {
        verifyFresh(user, sessionId, pin, "Unlock the Customer App before approving this transfer", "The PIN did not match");
    }

    private void verifyFresh(User user, UUID sessionId, String pin, String unlockMessage, String mismatchMessage) {
        users.findLockedById(user.getId()).orElseThrow(this::invalidTicket);
        AuthSession session = valid(sessions.findLockedById(sessionId).orElseThrow(this::invalidTicket));
        if (!user.isProfileComplete() || !session.getUser().getId().equals(user.getId())
                || sessionService.isPinLocked(sessionId))
            throw new PinRejected("PIN_REQUIRED", unlockMessage);
        Pin saved = pin(user.getId());
        if (saved == null) throw new PinRejected("PIN_SETUP_REQUIRED", "Create your PIN first");
        if (saved.failures() >= 5) throw new PinRejected("PIN_RECOVERY_REQUIRED", "Verify your identity to reset your PIN");
        if (!encoder.matches(secret(user.getId(), pin), saved.hash())) {
            int failures = saved.failures() + 1;
            jdbc.update("UPDATE customer_app_pins SET failed_attempts=? WHERE user_id=?", failures, user.getId());
            if (failures >= 5) jdbc.update("UPDATE app_pin_locks SET locked=TRUE WHERE session_id IN (SELECT id FROM auth_sessions WHERE user_id=?)", user.getId());
            throw new PinRejected(failures >= 5 ? "PIN_RECOVERY_REQUIRED" : "PIN_INVALID", mismatchMessage);
        }
        jdbc.update("UPDATE customer_app_pins SET failed_attempts=0 WHERE user_id=?", user.getId());
    }

    /** Verifies the PIN for one upcoming transfer; failures share the persistent five-attempt counter. */
    @Transactional(noRollbackFor = PinRejected.class)
    public TransferProof verifyForTransfer(User user, UUID sessionId, String pin) {
        continuation.requireCustomer(user);
        users.findLockedById(user.getId()).orElseThrow(this::invalidTicket);
        AuthSession session = valid(sessions.findLockedById(sessionId).orElseThrow(this::invalidTicket));
        if (!session.getUser().getId().equals(user.getId()) || sessionService.isPinLocked(sessionId))
            throw new PinRejected("PIN_REQUIRED", "Unlock the app before confirming a transfer");
        Pin saved = pin(user.getId());
        if (saved == null) throw new PinRejected("PIN_SETUP_REQUIRED", "Create your PIN first");
        if (saved.failures() >= 5) throw new PinRejected("PIN_RECOVERY_REQUIRED", "Verify your identity to reset your PIN");
        if (!encoder.matches(secret(user.getId(), pin), saved.hash())) {
            int failures = saved.failures() + 1;
            jdbc.update("UPDATE customer_app_pins SET failed_attempts=? WHERE user_id=?", failures, user.getId());
            if (failures >= 5) jdbc.update("UPDATE app_pin_locks SET locked=TRUE WHERE session_id IN (SELECT id FROM auth_sessions WHERE user_id=?)", user.getId());
            throw new PinRejected(failures >= 5 ? "PIN_RECOVERY_REQUIRED" : "PIN_INVALID", "The PIN did not match");
        }
        jdbc.update("UPDATE customer_app_pins SET failed_attempts=0 WHERE user_id=?", user.getId());
        jdbc.update("DELETE FROM transfer_pin_proofs WHERE expires_at < CURRENT_TIMESTAMP - INTERVAL '1 day'");
        byte[] random = new byte[32]; RANDOM.nextBytes(random);
        String raw = Base64.getUrlEncoder().withoutPadding().encodeToString(random);
        jdbc.update("INSERT INTO transfer_pin_proofs(proof_hash,user_id,session_id,expires_at) VALUES (?,?,?,?)",
                HashUtils.sha256(raw), user.getId(), sessionId, OffsetDateTime.now().plusSeconds(TRANSFER_PROOF_SECONDS));
        audit.successAs(user, "AUTH", "TRANSFER_PIN_VERIFIED", sessionId.toString());
        return new TransferProof(raw, TRANSFER_PROOF_SECONDS);
    }

    /** Consumes a proof inside the transfer's transaction, so a failed transfer leaves it usable until expiry. */
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.MANDATORY)
    public void consumeTransferProof(User user, UUID sessionId, String raw) {
        int used = raw == null || sessionId == null || raw.length() > 128 ? 0 : jdbc.update("""
            UPDATE transfer_pin_proofs SET used_at=CURRENT_TIMESTAMP
            WHERE proof_hash=? AND user_id=? AND session_id=? AND used_at IS NULL AND expires_at > CURRENT_TIMESTAMP
            """, HashUtils.sha256(raw), user.getId(), sessionId);
        if (used != 1) throw new PinRejected("TRANSFER_PIN_REQUIRED", "Confirm this transfer with your PIN");
    }

    @Transactional
    public void discard(String raw) {
        Ticket ticket = ticket(raw);
        sessionService.logout(ticket.session().getId());
    }
    private String secret(long userId, String pin) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(pepper.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(("kesor-app-pin-v1:" + userId + ":" + pin).getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.GeneralSecurityException ex) { throw new IllegalStateException("PIN verification unavailable", ex); }
    }
}
