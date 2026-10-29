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
