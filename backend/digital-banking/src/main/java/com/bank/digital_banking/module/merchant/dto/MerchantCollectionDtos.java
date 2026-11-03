package com.bank.digital_banking.module.merchant.dto;

import jakarta.validation.constraints.*;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

import static com.bank.digital_banking.module.merchant.dto.MerchantShopDtos.*;

/** M5 dashboard/wallet and M6 collection contracts. Money is exact decimal text. */
public final class MerchantCollectionDtos {
    private MerchantCollectionDtos() {}

    public record Totals(String currency, long count, String gross) {}
    public record Receipt(String reference, String currency, String amount, String paidCurrency, String paidAmount,
                             String payerName, String payerAccount, String requestReference, String orderReference,
                             OffsetDateTime paidAt) {}
    /** Today's totals use Asia/Phnom_Penh business days; collections are not profit. */
    public record Dashboard(Profile profile, String businessDate, List<Totals> today, List<Receipt> recent,
                            OffsetDateTime serverTime) {}

    public record Activity(String reference, String kind, String direction, String amount, String currency,
                           String payerName, String payerAccount, OffsetDateTime createdAt) {}
    public record WalletDetail(Wallet wallet, List<Activity> activity, int page, boolean hasMore) {}

    public record ShopQr(String qrString, String currency, String accountNumber, String storeName, String merchantId) {}

    @Getter @Setter
    public static class NewPaymentRequest {
        @NotBlank @Pattern(regexp = "(?i)USD|KHR") private String currency;
        @NotNull @Positive private BigDecimal amount;
        @Size(max = 50) private String orderReference;
        @com.fasterxml.jackson.annotation.JsonAnySetter
        void unknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }

    public record PaymentRequestView(UUID requestId, String reference, String status, String currency, String amount,
                                     String orderReference, String qrString, OffsetDateTime createdAt,
                                     OffsetDateTime expiresAt, OffsetDateTime serverTime, Receipt receipt) {}
    public record CreatedRequest(boolean created, PaymentRequestView request) {}
}
