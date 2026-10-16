package com.bank.digital_banking.module.auth.service;
import com.bank.digital_banking.module.auth.dto.OtpResponseDto;
public interface OtpService {
    OtpResponseDto generateAndSendOtp(String email, String purpose, boolean deliver);
    void validateOtp(String email, String inputCode, String purpose);
}
