package com.bank.digital_banking.module.auth.dto;
import jakarta.validation.constraints.*;
import lombok.Data;
@Data
public class LoginRequestDto {
    @NotBlank @Size(max=100) private String usernameOrEmail;
    @NotBlank @Size(max=72)
    @com.bank.digital_banking.common.validation.Utf8Size(max=72) private String password;
    @NotBlank @Pattern(regexp="[0-9]{6}") private String otpCode;
    @NotBlank @Size(max=255) private String deviceFingerprint;
    @NotBlank @Size(max=100) private String deviceName;
    @Size(max=50) private String deviceType;
}
