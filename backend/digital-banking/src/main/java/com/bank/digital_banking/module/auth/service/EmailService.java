package com.bank.digital_banking.module.auth.service;

public interface EmailService {

    void sendOtpEmail(String toEmail, String otpCode, String purpose);
}