package com.bank.digital_banking.module.payment.qr;

/**
 * Standard EMVCo Merchant-Presented Mode (MPM) Tag and Sub-tag definitions.
 * Follows EMVCo QR Code Specification for Payment Systems (CPM/MPM).
 */
public final class EmvcoTag {

    private EmvcoTag() {}

    // Top-level EMVCo Data Objects
    public static final String PAYLOAD_FORMAT_INDICATOR = "00";      // Length 02, Value: "01"
    public static final String POINT_OF_INITIATION_METHOD = "01";    // Length 02, "11" = Static, "12" = Dynamic
    public static final String MERCHANT_ACCOUNT_INFORMATION = "29";  // Merchant / Individual Account Information
    public static final String MERCHANT_ACCOUNT_INFORMATION_ALT = "30";
    public static final String MERCHANT_CATEGORY_CODE = "52";        // Length 04, e.g. "5999"
    public static final String TRANSACTION_CURRENCY = "53";          // Length 03, ISO 4217 numeric (USD = "840", KHR = "116")
    public static final String TRANSACTION_AMOUNT = "54";            // Up to 13 digits with decimal
    public static final String COUNTRY_CODE = "58";                  // Length 02, e.g. "KH"
    public static final String MERCHANT_NAME = "59";                 // Up to 25 characters
    public static final String MERCHANT_CITY = "60";                 // Up to 15 characters
    public static final String POSTAL_CODE = "61";                   // Up to 10 characters
    public static final String ADDITIONAL_DATA_TEMPLATE = "62";      // Additional Data Field Template
    public static final String CRC = "63";                           // Length 04, 16-bit CRC hex

    // Sub-tags inside Merchant Account Information (Tag 29 / 30)
    public static final String SUBTAG_GUID = "00";                   // Globally Unique Identifier (e.g. "bank@digitalbank")
    public static final String SUBTAG_ACCOUNT_ID = "01";             // Account Number or identifier (e.g. "9000000001@digitalbank")
    public static final String SUBTAG_ACQUIRING_BANK = "02";         // Acquiring Bank name/code (e.g. "Digital Bank")
    public static final String SUBTAG_ACCOUNT_TYPE = "03";           // Optional account classification

    // Sub-tags inside Additional Data Template (Tag 62)
    public static final String SUBTAG_BILL_NUMBER = "01";            // Invoice / Bill Number
    public static final String SUBTAG_MOBILE_NUMBER = "02";          // Mobile Number
    public static final String SUBTAG_STORE_LABEL = "03";            // Store Label
    public static final String SUBTAG_LOYALTY_NUMBER = "04";         // Loyalty Number
    public static final String SUBTAG_REFERENCE_LABEL = "05";        // Reference Label / Tracking ID
    public static final String SUBTAG_CUSTOMER_LABEL = "06";         // Customer Label
    public static final String SUBTAG_TERMINAL_LABEL = "07";         // Terminal Label
    public static final String SUBTAG_PURPOSE_TRANSACTION = "08";    // Purpose of Transaction / Remark
    public static final String SUBTAG_ADDITIONAL_CONSUMER_DATA = "09";

    // Currency Constants
    public static final String CURRENCY_USD_CODE = "840";
    public static final String CURRENCY_KHR_CODE = "116";

    // Initiation Method Values
    public static final String POINT_OF_INITIATION_STATIC = "11";
    public static final String POINT_OF_INITIATION_DYNAMIC = "12";
}
