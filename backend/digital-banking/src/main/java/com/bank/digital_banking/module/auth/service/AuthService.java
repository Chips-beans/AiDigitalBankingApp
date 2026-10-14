package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.module.auth.dto.LoginRequestDto;
import com.bank.digital_banking.module.auth.dto.RefreshTokenRequestDto;
import com.bank.digital_banking.module.auth.dto.RegisterRequestDto;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;

public interface AuthService {

    void requestOtp(String email, String purpose);

    TokenResponseDto register(RegisterRequestDto request, String clientIp);

    TokenResponseDto login(LoginRequestDto request, String clientIp);

    TokenResponseDto refreshToken(RefreshTokenRequestDto request);
}