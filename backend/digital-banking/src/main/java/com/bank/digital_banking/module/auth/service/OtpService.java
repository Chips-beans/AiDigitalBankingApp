package com.bank.digital_banking.module.auth.service;

public interface OtpService {

    void generateAndSendOtp(String email, String purpose);

    void validateOtp(String email, String inputCode, String purpose);
}