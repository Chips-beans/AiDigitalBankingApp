package com.bank.digital_banking.module.auth.dto;
import jakarta.validation.constraints.*;
import lombok.Data;
@Data
public class RegisterRequestDto {
    @NotBlank @Size(min=3, max=50) @Pattern(regexp="[A-Za-z0-9_.-]+") private String username;
    @NotBlank @Email @Size(max=100) private String email;
    @NotBlank @Size(min=8, max=72) private String password;
    @NotBlank @Pattern(regexp="[0-9]{6}") private String otpCode;
    @Size(max=50) private String firstName;
    @Size(max=50) private String lastName;
    @NotBlank @Size(max=255) private String deviceFingerprint;
    @NotBlank @Size(max=100) private String deviceName;
    @Size(max=50) private String deviceType;
}
