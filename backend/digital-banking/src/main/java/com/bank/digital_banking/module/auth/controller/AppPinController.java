package com.bank.digital_banking.module.auth.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.service.AppPinService;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.UUID;

@RestController @RequestMapping("/api/v1/auth/pin") @RequiredArgsConstructor
public class AppPinController {
    private final AppPinService pins;
    public record TicketRequest(@NotBlank @Size(max=128) String ticket) {}
    public record UnlockRequest(@NotBlank @Size(max=128) String ticket, @NotBlank @Pattern(regexp="[0-9]{4}") String pin) {}
    public record SetupRequest(@NotBlank @Size(max=128) String ticket, @NotBlank @Pattern(regexp="[0-9]{4}") String pin,
                               @NotBlank @Pattern(regexp="[0-9]{4}") String confirmPin, Boolean reset) {}
    @ModelAttribute public void noStore(HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store"); response.setHeader("Pragma", "no-cache");
    }
    @PostMapping("/prepare") public ApiResponse<AppPinService.Challenge> prepare(@AuthenticationPrincipal User user, Authentication auth) {
        return ApiResponse.success(pins.prepare(user, (UUID) auth.getDetails()), "PIN required");
    }
    @PostMapping("/status") public ApiResponse<AppPinService.Challenge> status(@Valid @RequestBody TicketRequest request) {
        return ApiResponse.success(pins.lock(request.ticket()), "App locked");
    }
    @PostMapping("/setup") public ApiResponse<TokenResponseDto> setup(@Valid @RequestBody SetupRequest request) {
        return ApiResponse.success(pins.setup(request.ticket(), request.pin(), request.confirmPin(), Boolean.TRUE.equals(request.reset())), "PIN saved");
    }
    @PostMapping("/unlock") public ApiResponse<TokenResponseDto> unlock(@Valid @RequestBody UnlockRequest request) {
        return ApiResponse.success(pins.unlock(request.ticket(), request.pin()), "App unlocked");
    }
    @PostMapping("/discard") public ApiResponse<Void> discard(@Valid @RequestBody TicketRequest request) {
        pins.discard(request.ticket()); return ApiResponse.success("App credential revoked");
    }
}
