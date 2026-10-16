package com.bank.digital_banking.module.auth.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import java.time.OffsetDateTime;

@Entity
@Table(name = "login_attempt_limits")
@Getter @Setter @NoArgsConstructor
public class LoginAttemptLimit {
    @Id @Column(length = 128)
    private String id;
    @Column(nullable = false)
    private OffsetDateTime windowStartedAt;
    @Column(nullable = false)
    private int attemptCount;
}
