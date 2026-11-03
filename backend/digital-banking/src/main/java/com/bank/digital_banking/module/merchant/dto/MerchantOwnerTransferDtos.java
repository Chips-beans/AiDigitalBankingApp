package com.bank.digital_banking.module.merchant.dto;

import jakarta.validation.constraints.*;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * M8 owner transfers: a shop's business wallet to the same owner's own personal wallet.
 * Money is exact decimal text. The destination is never part of a request.
 */
public final class MerchantOwnerTransferDtos {
    private MerchantOwnerTransferDtos() {}

    @Getter @Setter
    public static class NewOwnerTransfer {
        @NotBlank @Pattern(regexp = "[0-9]{10,20}") private String sourceAccountNumber;
        @NotNull @Positive private BigDecimal amount;
        @com.fasterxml.jackson.annotation.JsonAnySetter
        void unknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }

    public record TransferReceipt(String reference, OffsetDateTime completedAt) {}

    /**
     * {@code approvalUri} and {@code state} are present only when the intent is created or its
     * creation is replayed while still waiting; the handoff secret is never readable again.
     */
    public record TransferView(UUID intentId, String status, String sourceAccountNumber, String destinationAccount,
                               String currency, String amount, OffsetDateTime createdAt, OffsetDateTime expiresAt,
                               OffsetDateTime serverTime, String failureCode, TransferReceipt receipt,
                               String approvalUri, String state) {}
    public record CreatedTransfer(boolean created, TransferView transfer) {}

    /** What the Customer App shows before the owner approves with the PIN. */
    public record TransferDetails(UUID intentId, String shopName, String sourceAccount, String destinationAccount,
                                  String currency, String amount, String status, OffsetDateTime expiresAt,
                                  OffsetDateTime serverTime, String merchantPackage) {}

    /** Result of an approval or denial; {@code status} is COMPLETED, FAILED or DENIED. */
    public record TransferOutcome(UUID intentId, String status, String failureCode, String callbackUri,
                                  String merchantPackage) {}
}
