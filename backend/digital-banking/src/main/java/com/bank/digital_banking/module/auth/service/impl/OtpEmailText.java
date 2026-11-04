package com.bank.digital_banking.module.auth.service.impl;

/** One wording for the OTP email, whichever transport (SMTP or Gmail API) delivers it. */
final class OtpEmailText {
    private OtpEmailText() { }
    static String subject(String purpose) { return "Digital Wallet verification " + purpose; }
    static String body(String otp, int expiryMinutes) {
        return "Your verification code is " + otp + ". It expires in " + expiryMinutes + " minutes. Do not share this code.";
    }
}
