package com.bank.digital_banking.module.payment.service;

import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.payment.dto.*;

public interface QrPaymentService {

    /**
     * Generates a fully functional EMVCo QR code payload and returns all data needed to render or generate it.
     */
    QrGenerateResponse generateQr(User user, QrGenerateRequest request);

    /** Backward-compatible response for the legacy KHQR generation endpoint. */
    KhqrGenerateResponse generateKhqr(User user, KhqrGenerateRequest request);

    /**
     * Decodes and validates a scanned QR code, providing payment preview details before confirming transfer.
     */
    QrScanResponse scanQr(User user, QrScanRequest request);

    /**
     * Executes transfer payment to the account encoded in the scanned QR code.
     */
    QrTransferResponse processQrTransfer(User user, String idempotencyKey, QrTransferRequest request,
                                         com.bank.digital_banking.module.transaction.service.FinancialCommandService.PinProof proof);

    /**
     * Checks payment settlement status for a given QR hash.
     */
    PaymentCheckStatusResponse verifyPaymentStatus(User user, String qrHash);

    /**
     * Asynchronous settlement notification (webhook endpoint).
     */
    void processWebhookNotification(QrWebhookPayload payload);
}
