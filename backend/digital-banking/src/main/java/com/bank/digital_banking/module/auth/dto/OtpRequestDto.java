package com.bank.digital_banking.module.auth.dto;
import jakarta.validation.constraints.*;
import lombok.Data;
@Data
public class OtpRequestDto {
    @NotBlank @Email @Size(max=100) private String email;
    @NotBlank @Pattern(regexp="SIGNUP|LOGIN") private String purpose;
}
