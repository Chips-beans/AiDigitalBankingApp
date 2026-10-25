package com.bank.digital_banking.module.payment.qr;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.HashUtils;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Pure Java EMVCo QR Code Engine built from scratch.
 * Implements EMVCo Merchant-Presented Mode (MPM) specification and provides full parity
 * with KHQR-style standard QR formats without external library dependencies.
 */
@Component
@RequiredArgsConstructor
public class QrCodeEngine {

    private final QrProperties properties;

    /**
     * Options for generating an EMVCo-compliant QR payload.
     */
    public record GenerateOptions(
            String accountNumber,
            String payeeName,
            BigDecimal amount,
            String currency,
            String remark,
            String billNumber,
            String terminalLabel,
            boolean dynamic
    ) {}

    /**
     * Generates a fully functional EMVCo QR code payload.
     */
    public EmvcoQrCode generate(GenerateOptions options) {
        if (options.accountNumber() == null || options.accountNumber().trim().isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Account number is required for QR code");
        }

        String currencyStr = options.currency() != null ? options.currency().trim().toUpperCase() : properties.getDefaultCurrency();
        String currencyCode = toCurrencyNumericCode(currencyStr);

        boolean isDynamic = options.dynamic() || (options.amount() != null && options.amount().compareTo(BigDecimal.ZERO) > 0);
        String pointOfInitiation = isDynamic ? EmvcoTag.POINT_OF_INITIATION_DYNAMIC : EmvcoTag.POINT_OF_INITIATION_STATIC;

        String payeeName = options.payeeName() != null && !options.payeeName().trim().isEmpty()
                ? options.payeeName().trim()
                : properties.getMerchantName();
        if (payeeName.length() > 25) {
            payeeName = payeeName.substring(0, 25);
        }

        String merchantCity = properties.getMerchantCity();
        if (merchantCity.length() > 15) {
            merchantCity = merchantCity.substring(0, 15);
        }

        EmvcoTlvBuilder builder = new EmvcoTlvBuilder();
        builder.addTag(EmvcoTag.PAYLOAD_FORMAT_INDICATOR, "01");
        builder.addTag(EmvcoTag.POINT_OF_INITIATION_METHOD, pointOfInitiation);

        // Account Information Template (Tag 29)
        Map<String, String> accountSubTags = new LinkedHashMap<>();
        accountSubTags.put(EmvcoTag.SUBTAG_GUID, properties.getGuid());
        String accountIdentifier = options.accountNumber().contains("@")
                ? options.accountNumber()
                : options.accountNumber() + "@digitalbank";
        accountSubTags.put(EmvcoTag.SUBTAG_ACCOUNT_ID, accountIdentifier);
        accountSubTags.put(EmvcoTag.SUBTAG_ACQUIRING_BANK, properties.getAcquiringBank());
        builder.addTemplate(EmvcoTag.MERCHANT_ACCOUNT_INFORMATION, accountSubTags);

        // Merchant Category Code (Tag 52)
        builder.addTag(EmvcoTag.MERCHANT_CATEGORY_CODE, "5999");

        // Transaction Currency (Tag 53)
        builder.addTag(EmvcoTag.TRANSACTION_CURRENCY, currencyCode);

        // Transaction Amount (Tag 54) - included if dynamic or amount specified
        String formattedAmount = null;
        BigDecimal finalAmount = null;
        if (options.amount() != null && options.amount().compareTo(BigDecimal.ZERO) > 0) {
            finalAmount = options.amount();
            if ("KHR".equalsIgnoreCase(currencyStr)) {
                // KHR typically whole units or up to 2 decimal places
                formattedAmount = finalAmount.stripTrailingZeros().toPlainString();
            } else {
                formattedAmount = finalAmount.setScale(2, RoundingMode.HALF_UP).toPlainString();
            }
            builder.addTag(EmvcoTag.TRANSACTION_AMOUNT, formattedAmount);
        }

        // Country Code (Tag 58)
        builder.addTag(EmvcoTag.COUNTRY_CODE, properties.getCountryCode());

        // Merchant / Payee Name (Tag 59)
        builder.addTag(EmvcoTag.MERCHANT_NAME, payeeName);

        // Merchant City (Tag 60)
        builder.addTag(EmvcoTag.MERCHANT_CITY, merchantCity);

        // Additional Data Template (Tag 62)
        Map<String, String> additionalSubTags = new LinkedHashMap<>();
        if (options.billNumber() != null && !options.billNumber().trim().isEmpty()) {
            additionalSubTags.put(EmvcoTag.SUBTAG_BILL_NUMBER, options.billNumber().trim());
        }
        if (options.terminalLabel() != null && !options.terminalLabel().trim().isEmpty()) {
            additionalSubTags.put(EmvcoTag.SUBTAG_TERMINAL_LABEL, options.terminalLabel().trim());
        }
        if (options.remark() != null && !options.remark().trim().isEmpty()) {
            String remark = options.remark().trim();
            if (remark.length() > 50) {
                remark = remark.substring(0, 50);
            }
            additionalSubTags.put(EmvcoTag.SUBTAG_PURPOSE_TRANSACTION, remark);
        }
        if (!additionalSubTags.isEmpty()) {
            builder.addTemplate(EmvcoTag.ADDITIONAL_DATA_TEMPLATE, additionalSubTags);
        }

        // Build with CRC-16
        String fullQrString = builder.buildWithCrc();
        String qrHash = HashUtils.md5(fullQrString);
        String crc = fullQrString.substring(fullQrString.length() - 4);

        return EmvcoQrCode.builder()
                .qrString(fullQrString)
                .qrHash(qrHash)
                .payloadFormatIndicator("01")
                .pointOfInitiationMethod(pointOfInitiation)
                .dynamic(isDynamic)
                .accountNumber(extractCleanAccountNumber(options.accountNumber()))
                .accountIdentifier(accountIdentifier)
                .acquiringBank(properties.getAcquiringBank())
                .accountType("INDIVIDUAL")
                .merchantCategoryCode("5999")
                .currency(currencyStr)
                .currencyNumericCode(currencyCode)
                .amount(finalAmount)
                .countryCode(properties.getCountryCode())
                .payeeName(payeeName)
                .merchantCity(merchantCity)
                .billNumber(options.billNumber())
                .referenceLabel(null)
                .remark(options.remark())
                .crc(crc)
                .tags(builder.buildWithoutCrc().length() > 0 ? EmvcoTlvParser.parse(builder.buildWithoutCrc()) : Map.of())
                .accountSubTags(accountSubTags)
                .additionalDataSubTags(additionalSubTags)
                .build();
    }

    /**
     * Parses and strictly validates any EMVCo QR code string.
     */
    public EmvcoQrCode parse(String qrString) {
        if (qrString == null || qrString.trim().isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_CODE", "QR code string is required");
        }

        String trimmed = qrString.trim();

        // 1. Verify CRC-16 Checksum
        if (!Crc16Ccitt.verify(trimmed)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_CHECKSUM", "QR code CRC checksum validation failed");
        }

        // 2. Parse TLV Tags
        Map<String, String> tags = EmvcoTlvParser.parse(trimmed);

        // 3. Validate Payload Format Indicator (Tag 00)
        String formatIndicator = tags.get(EmvcoTag.PAYLOAD_FORMAT_INDICATOR);
        if (!"01".equals(formatIndicator)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "Unsupported QR payload format: " + formatIndicator);
        }

        // 4. Point of Initiation Method (Tag 01)
        String pointOfInitiation = tags.get(EmvcoTag.POINT_OF_INITIATION_METHOD);
        boolean isDynamic = EmvcoTag.POINT_OF_INITIATION_DYNAMIC.equals(pointOfInitiation);

        // 5. Account Information (Tag 29 or Tag 30)
        String accountTemplate = tags.get(EmvcoTag.MERCHANT_ACCOUNT_INFORMATION);
        if (accountTemplate == null) {
            accountTemplate = tags.get(EmvcoTag.MERCHANT_ACCOUNT_INFORMATION_ALT);
        }
        if (accountTemplate == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_DATA", "Missing account information in QR code (Tag 29/30)");
        }

        Map<String, String> accountSubTags = EmvcoTlvParser.parseSubTags(accountTemplate);
        String accountIdentifier = accountSubTags.get(EmvcoTag.SUBTAG_ACCOUNT_ID);
        if (accountIdentifier == null || accountIdentifier.trim().isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_DATA", "Missing account identifier in QR account data");
        }

        String cleanAccountNumber = extractCleanAccountNumber(accountIdentifier);
        String acquiringBank = accountSubTags.getOrDefault(EmvcoTag.SUBTAG_ACQUIRING_BANK, properties.getAcquiringBank());

        // 6. Currency (Tag 53)
        String currencyNumeric = tags.get(EmvcoTag.TRANSACTION_CURRENCY);
        String currency = fromCurrencyNumericCode(currencyNumeric);

        // 7. Amount (Tag 54)
        BigDecimal amount = null;
        String amountStr = tags.get(EmvcoTag.TRANSACTION_AMOUNT);
        if (amountStr != null && !amountStr.trim().isEmpty()) {
            try {
                amount = new BigDecimal(amountStr.trim());
            } catch (NumberFormatException e) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_AMOUNT", "Malformed amount in QR code: " + amountStr);
            }
        }

        // 8. Payee Name & City (Tag 59 & 60)
        String payeeName = tags.getOrDefault(EmvcoTag.MERCHANT_NAME, "Digital Bank User");
        String merchantCity = tags.getOrDefault(EmvcoTag.MERCHANT_CITY, properties.getMerchantCity());
        String countryCode = tags.getOrDefault(EmvcoTag.COUNTRY_CODE, properties.getCountryCode());
        String mcc = tags.getOrDefault(EmvcoTag.MERCHANT_CATEGORY_CODE, "5999");

        // 9. Additional Data (Tag 62)
        String additionalDataTemplate = tags.get(EmvcoTag.ADDITIONAL_DATA_TEMPLATE);
        Map<String, String> additionalSubTags = additionalDataTemplate != null
                ? EmvcoTlvParser.parseSubTags(additionalDataTemplate)
                : Map.of();

        String billNumber = additionalSubTags.get(EmvcoTag.SUBTAG_BILL_NUMBER);
        String referenceLabel = additionalSubTags.get(EmvcoTag.SUBTAG_REFERENCE_LABEL);
        String remark = additionalSubTags.get(EmvcoTag.SUBTAG_PURPOSE_TRANSACTION);

        String crc = tags.get(EmvcoTag.CRC);
        String qrHash = HashUtils.md5(trimmed);

        return EmvcoQrCode.builder()
                .qrString(trimmed)
                .qrHash(qrHash)
                .payloadFormatIndicator(formatIndicator)
                .pointOfInitiationMethod(pointOfInitiation)
                .dynamic(isDynamic)
                .accountNumber(cleanAccountNumber)
                .accountIdentifier(accountIdentifier)
                .acquiringBank(acquiringBank)
                .accountType("INDIVIDUAL")
                .merchantCategoryCode(mcc)
                .currency(currency)
                .currencyNumericCode(currencyNumeric)
                .amount(amount)
                .countryCode(countryCode)
                .payeeName(payeeName)
                .merchantCity(merchantCity)
                .billNumber(billNumber)
                .referenceLabel(referenceLabel)
                .remark(remark)
                .crc(crc)
                .tags(tags)
                .accountSubTags(accountSubTags)
                .additionalDataSubTags(additionalSubTags)
                .build();
    }

    /**
     * Extracts pure account digits from identifiers like "9000000001@digitalbank" or "store_name@bank" or "9000000001".
     */
    public static String extractCleanAccountNumber(String rawIdentifier) {
        if (rawIdentifier == null) return null;
        String trimmed = rawIdentifier.trim();
        if (trimmed.contains("@")) {
            return trimmed.substring(0, trimmed.indexOf("@"));
        }
        return trimmed;
    }

    public static String toCurrencyNumericCode(String currency) {
        if ("KHR".equalsIgnoreCase(currency)) {
            return EmvcoTag.CURRENCY_KHR_CODE;
        }
        return EmvcoTag.CURRENCY_USD_CODE;
    }

    public static String fromCurrencyNumericCode(String numericCode) {
        if (EmvcoTag.CURRENCY_KHR_CODE.equals(numericCode)) {
            return "KHR";
        }
        return "USD";
    }
}
