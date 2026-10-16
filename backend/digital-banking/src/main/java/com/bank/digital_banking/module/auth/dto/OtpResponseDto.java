package com.bank.digital_banking.module.auth.dto;
public record OtpResponseDto(String message, int expiresInSeconds, int resendAfterSeconds) {}
