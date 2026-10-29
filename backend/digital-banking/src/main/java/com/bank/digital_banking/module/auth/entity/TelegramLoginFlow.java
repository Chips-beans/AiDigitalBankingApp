package com.bank.digital_banking.module.auth.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity @Table(name = "telegram_login_flows")
@Getter @Setter @NoArgsConstructor
public class TelegramLoginFlow {
    @Id @Column(length = 64) private String id;
    @Column(nullable = false, length = 64) private String exchangeSecretHash;
    @Column(length = 64) private String approvalReceiptHash;
    @Column(nullable = false, length = 128) private String verifier;
    @Column(nullable = false, length = 64) private String nonce;
    @Column(nullable = false) private OffsetDateTime expiresAt;
    @Column(nullable = false) private boolean callbackHandled;
    @Column(nullable = false) private boolean claimed;
    @Column(length = 128) private String subject;
    @Column(length = 50) private String firstName;
    @Column(length = 50) private String lastName;
    @Column(length = 40) private String errorCode;
    private Long linkedUserId;
    private UUID linkedSessionId;
    @Column(nullable = false, length = 255) private String deviceFingerprint;
    @Column(nullable = false, length = 100) private String deviceName;
    @Column(length = 50) private String deviceType;
    @Column(length = 255) private String ipAddress;
}
