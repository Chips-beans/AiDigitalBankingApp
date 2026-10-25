package com.bank.digital_banking.module.payment.qr;

import lombok.Builder;
import lombok.Getter;
import lombok.ToString;

import java.math.BigDecimal;
import java.util.Map;

@Getter
@Builder
@ToString
public class EmvcoQrCode {

    private final String qrString;
    private final String qrHash; // MD5 hash of qrString
    private final String payloadFormatIndicator;
    private final String pointOfInitiationMethod;
    private final boolean dynamic;

    // Recipient Account Info
    private final String accountNumber;
    private final String accountIdentifier;
    private final String acquiringBank;
    private final String accountType;

    // Financial & Merchant Details
    private final String merchantCategoryCode;
    private final String currency;
    private final String currencyNumericCode;
    private final BigDecimal amount;
    private final String countryCode;
    private final String payeeName;
    private final String merchantCity;

    // Additional Template Details (Tag 62)
    private final String billNumber;
    private final String referenceLabel;
    private final String remark;

    // Integrity Check
    private final String crc;

    // Raw Parsed Tags
    private final Map<String, String> tags;
    private final Map<String, String> accountSubTags;
    private final Map<String, String> additionalDataSubTags;
}
