package com.bank.digital_banking.module.merchant.dto;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import jakarta.validation.constraints.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/** M4 self-service shop contracts. Owner, shop code, QR alias, status and balances are server-controlled. */
public final class MerchantShopDtos {
    private MerchantShopDtos() {}

    /** Unknown fields (ownerUserId, merchantId, status, openingBalance, aliases...) fail the request. */
    abstract static class Strict {
        @JsonAnySetter
        void unknown(String name, Object value) {
            throw new IllegalArgumentException("Unsupported field");
        }
    }

    @Getter @Setter
    public static class Registration extends Strict {
        @NotBlank @Size(max = 150) private String storeName;
        @NotBlank @Size(max = 32) private String categoryCode;
        @NotBlank @Size(max = 24) private String phone;
        @NotBlank @Size(max = 100) private String city;
        @NotBlank @Size(max = 255) private String address;
        @Size(max = 500) private String description;
        private UUID stagedLogoId;
    }

    /** Partial edit guarded by the version the client last read. */
    @Getter @Setter
    public static class ProfileUpdate extends Strict {
        @NotNull @PositiveOrZero private Long version;
        @Size(min = 1, max = 150) private String storeName;
        @Size(max = 32) private String categoryCode;
        @Size(max = 24) private String phone;
        @Size(min = 1, max = 100) private String city;
        @Size(min = 1, max = 255) private String address;
        @Size(max = 500) private String description;
        private UUID stagedLogoId;
        private Boolean removeLogo;
    }

    public record Owner(long id, String displayName) {}
    public record Shop(String merchantId, String storeName, String categoryCode, String phone, String city,
                       String address, String description, String status, String logoId, long version,
                       OffsetDateTime createdAt) {}
    public record Wallet(String accountNumber, String category, String merchantId, String currency,
                         String status, String balance) {}
    public record Profile(String onboardingState, Owner owner, Shop shop, List<Wallet> wallets) {}
    public record Registered(boolean created, Profile profile) {}
    public record StagedLogo(UUID logoId, String contentType, int width, int height, OffsetDateTime expiresAt) {}
    public record Logo(String contentType, byte[] data) {}
    public record Category(String code, String mcc) {}
}
