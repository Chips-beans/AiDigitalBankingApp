package com.bank.digital_banking.module.payment.controller;

import com.bank.digital_banking.module.payment.dto.*;
import com.bank.digital_banking.module.payment.service.BakongService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/payments")
@RequiredArgsConstructor
public class BakongPaymentController {

    private final BakongService bakongService;

    @PostMapping("/khqr/generate")
    public ResponseEntity<KhqrGenerateResponse> generateKhqr(@Valid @RequestBody KhqrGenerateRequest request) {
        KhqrGenerateResponse response = bakongService.generateKhqr(request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/verify/{md5Hash}")
    public ResponseEntity<PaymentCheckStatusResponse> verifyPaymentStatus(@PathVariable String md5Hash) {
        PaymentCheckStatusResponse response = bakongService.verifyPaymentStatus(md5Hash);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/webhook")
    public ResponseEntity<Void> handleBakongWebhook(@RequestBody BakongWebhookPayload payload) {
        bakongService.processWebhookNotification(payload);
        return ResponseEntity.ok().build();
    }
}