package com.bank.digital_banking.module.auth.dto;
import com.bank.digital_banking.module.auth.entity.User;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
public record SessionIdentityDto(Long userId, String username, String email, Set<String> roles, UUID sessionId,
                                 boolean profileComplete, String firstName, String lastName, boolean telegramLinked) {
    public static SessionIdentityDto from(User user, UUID sid) {
        return new SessionIdentityDto(user.getId(), user.getUsername(), user.getEmail(),
                user.getRoles().stream().map(r -> r.getName().name()).collect(Collectors.toSet()), sid,
                user.isProfileComplete(), user.getFirstName(), user.getLastName(), user.getTelegramSubject() != null);
    }
}
