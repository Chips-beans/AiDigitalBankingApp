package com.bank.digital_banking.module.auth.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.OffsetDateTime;

@Entity @Table(name = "otp_rate_limits")
@Getter @Setter @NoArgsConstructor
public class OtpRateLimit {
    @Id @Column(length = 130) private String id;
    @Column(nullable = false) private OffsetDateTime windowStartedAt;
    @Column(nullable = false) private int requestCount;
    private OffsetDateTime lastRequestedAt;
}
