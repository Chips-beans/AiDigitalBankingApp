package com.bank.digital_banking.module.merchant.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthRateLimiter;
import com.bank.digital_banking.module.merchant.service.MerchantSalesService;
import com.bank.digital_banking.module.merchant.dto.MerchantCollectionDtos.Receipt;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.UUID;

@RestController @RequestMapping("/api/v1/merchants/me") @RequiredArgsConstructor
@Tag(name = "Merchant sales and reports")
public class MerchantSalesController {
    private final MerchantSalesService sales;
    private final MerchantAuthRateLimiter limits;
    private <T> ResponseEntity<ApiResponse<T>> body(T value) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ApiResponse.success(value, "Merchant collections"));
    }
    @GetMapping("/sales")
    @Operation(summary = "Confirmed shop collections with filters, keyset paging and whole-filter totals")
    public ResponseEntity<ApiResponse<MerchantSalesService.Sales>> list(@AuthenticationPrincipal User user, Authentication auth,
            @RequestParam(required=false) String from, @RequestParam(required=false) String to,
            @RequestParam(required=false) String currency, @RequestParam(required=false) String q,
            @RequestParam(required=false) String cursor, @RequestParam(defaultValue="20") int size) {
        limits.check("sales-list", user.getId().toString(), 120);
        return body(sales.sales(user, (UUID) auth.getDetails(), from, to, currency, q, cursor, size));
    }
    @GetMapping("/sales/{reference}")
    @Operation(summary = "One owned payment-time receipt snapshot by transaction reference")
    public ResponseEntity<ApiResponse<Receipt>> receipt(@AuthenticationPrincipal User user, Authentication auth, @PathVariable String reference) {
        limits.check("sales-list", user.getId().toString(), 120);
        return body(sales.receipt(user, (UUID) auth.getDetails(), reference));
    }
    @GetMapping("/reports/collections")
    @Operation(summary = "Zero-filled daily or monthly collection buckets and separate currency totals")
    public ResponseEntity<ApiResponse<MerchantSalesService.Report>> report(@AuthenticationPrincipal User user, Authentication auth,
            @RequestParam(defaultValue="DAY") String period, @RequestParam(required=false) String from, @RequestParam(required=false) String to) {
        limits.check("sales-report", user.getId().toString(), 60);
        return body(sales.report(user, (UUID) auth.getDetails(), period, from, to));
    }
    @GetMapping("/payment-requests")
    @Operation(summary = "Shop request history by effective status, with bounded lazy expiry and no QR strings")
    public ResponseEntity<ApiResponse<MerchantSalesService.Requests>> requests(@AuthenticationPrincipal User user, Authentication auth,
            @RequestParam(required=false) String status, @RequestParam(required=false) String cursor, @RequestParam(defaultValue="20") int size) {
        limits.check("sales-list", user.getId().toString(), 120);
        return body(sales.requests(user, (UUID) auth.getDetails(), status, cursor, size));
    }
}
