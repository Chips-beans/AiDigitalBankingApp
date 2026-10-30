package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.dto.ContinuationDtos.*;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.*;

@Service @RequiredArgsConstructor
public class ContinuationPersistence {
    private final UserRepository users;
    private final RoleRepository roles;
    private final DeviceService devices;
    private final SessionService sessions;
    private final AuthSessionRepository authSessions;
    private final com.bank.digital_banking.module.account.service.AccountService accountService;
    private final JdbcTemplate jdbc;
    private final AuditTrail audit;

    private void identityLock(String identity) {
        jdbc.queryForObject("select pg_advisory_xact_lock(hashtextextended(?, 0))", Object.class, identity);
    }
    private User locked(long id) {
        return users.findLockedById(id).orElseThrow(() -> new AuthenticationFailedException("Profile is unavailable"));
    }
    public void requireCustomer(User user) {
        if (!user.isEnabled() || user.getRoles().stream().noneMatch(r -> r.getName() == ERole.ROLE_CUSTOMER))
            throw new AuthenticationFailedException("Unable to continue with this identity");
    }
    private User pending(String email, String subject, String first, String last) {
        Role customer = roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow();
        return users.save(User.builder().username("customer_" + UUID.randomUUID().toString().replace("-", ""))
                .email(email).telegramSubject(subject).firstName(first).lastName(last)
                .profileComplete(false).enabled(true).roles(Set.of(customer)).build());
    }
    private TokenResponseDto enter(User user, DeviceRequest request, String ip) {
        requireCustomer(user);
        Device device = devices.bind(user, request.deviceFingerprint(), request.deviceName(), request.deviceType(), null, ip);
        TokenResponseDto tokens = sessions.create(user, device);
        audit.successAs(user, "AUTH", "CONTINUE", user.getId().toString());
        return tokens;
    }
    @Transactional
    public TokenResponseDto email(String email, DeviceRequest device, String ip) {
        identityLock("email:" + email);
        User user = users.findByEmail(email).map(u -> locked(u.getId())).orElseGet(() -> pending(email, null, null, null));
        return enter(user, device, ip);
    }
    @Transactional
    public TokenResponseDto telegram(String subject, String first, String last, DeviceRequest device, String ip,
                                     Long linkedUserId, UUID linkedSessionId) {
        identityLock("telegram:" + subject);
        User existing = users.findByTelegramSubject(subject).orElse(null);
        User user;
        if (linkedUserId != null) {
            requireFreshLinkSession(linkedUserId, linkedSessionId);
            user = locked(linkedUserId);
            requireCustomer(user);
            if ((existing != null && !existing.getId().equals(user.getId()))
                    || (user.getTelegramSubject() != null && !subject.equals(user.getTelegramSubject())))
                throw new ApiException(HttpStatus.CONFLICT, "IDENTITY_ALREADY_LINKED", "This Telegram identity is already connected to a profile");
            user.setTelegramSubject(subject);
            audit.successAs(user, "AUTH", "TELEGRAM_LINKED", user.getId().toString());
        } else {
            user = existing == null ? pending(null, subject, first, last) : locked(existing.getId());
        }
        return enter(user, device, ip);
    }
    @Transactional(readOnly = true)
    public void requireFreshLinkSession(long userId, UUID sessionId) {
        AuthSession session = authSessions.findById(sessionId).orElseThrow(() -> new AuthenticationFailedException("Continue again before connecting Telegram"));
        if (!session.getUser().getId().equals(userId) || session.getRevokedAt() != null
                || !session.getExpiresAt().isAfter(OffsetDateTime.now())
                || session.getCreatedAt().isBefore(OffsetDateTime.now().minusMinutes(10))
                || session.getDevice().getStatus() != DeviceStatus.ACTIVE)
            throw new ApiException(HttpStatus.FORBIDDEN, "FRESH_AUTH_REQUIRED", "Continue again before connecting Telegram");
    }
    @Transactional
    public User complete(long userId, ProfileRequest request) {
        User user = locked(userId);
        requireCustomer(user);
        if (user.isProfileComplete()) {
            accountService.createDefaultUserWallets(user);
            return user;
        }
        user.setFirstName(request.firstName().strip());
        user.setLastName(request.lastName().strip());
        user.setProfileComplete(true);
        accountService.createDefaultUserWallets(user);
        audit.successAs(user, "AUTH", "PROFILE_COMPLETED", user.getId().toString());
        return user;
    }
    @Transactional
    public User updateDetails(long userId, ProfileRequest request) {
        User user = locked(userId);
        requireCustomer(user);
        if (!user.isProfileComplete()) throw new ApiException(HttpStatus.FORBIDDEN, "PROFILE_INCOMPLETE", "Complete your profile first");
        user.setFirstName(request.firstName().strip());
        user.setLastName(request.lastName().strip());
        audit.successAs(user, "AUTH", "PROFILE_UPDATED", user.getId().toString());
        return user;
    }
    @Transactional
    public TokenResponseDto linkEmail(long userId, String email, DeviceRequest device, String ip) {
        identityLock("email:" + email);
        User user = locked(userId);
        requireCustomer(user);
        if (user.getEmail() != null && !user.getEmail().equalsIgnoreCase(email))
            throw new ApiException(HttpStatus.CONFLICT, "IDENTITY_ALREADY_LINKED", "This profile already has an email identity");
        User existing = users.findByEmail(email).orElse(null);
        if (existing != null && !existing.getId().equals(userId)) {
            // Only an onboarding-only Telegram profile may be folded into a verified email profile.
            // It has never been authorized for banking. Complete profiles are never automatically merged.
            if (user.isProfileComplete() || user.getEmail() != null || user.getTelegramSubject() == null)
                throw new ApiException(HttpStatus.CONFLICT, "IDENTITY_ALREADY_LINKED", "Continue with this email to use its existing profile");
            User target = locked(existing.getId());
            requireCustomer(target);
            if (target.getTelegramSubject() != null)
                throw new ApiException(HttpStatus.CONFLICT, "IDENTITY_ALREADY_LINKED", "The email profile already has a Telegram identity");
            String subject = user.getTelegramSubject();
            user.setTelegramSubject(null);
            user.setEnabled(false);
            users.flush();
            target.setTelegramSubject(subject);
            authSessions.revokeForUser(userId, OffsetDateTime.now());
            audit.successAs(target, "AUTH", "TELEGRAM_LINKED", target.getId().toString());
            return enter(target, device, ip);
        }
        user.setEmail(email);
        audit.successAs(user, "AUTH", "EMAIL_LINKED", user.getId().toString());
        return enter(user, device, ip);
    }
}
