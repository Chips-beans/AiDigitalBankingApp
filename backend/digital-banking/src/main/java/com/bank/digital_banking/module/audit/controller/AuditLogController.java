package com.bank.digital_banking.module.audit.controller;

import com.bank.digital_banking.module.audit.dto.*;
import com.bank.digital_banking.module.audit.entity.AuditSeverity;
import com.bank.digital_banking.module.audit.service.AuditService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;

@RestController
@RequestMapping("/api/v1/audit")
@RequiredArgsConstructor
public class AuditLogController {

    private final AuditService auditService;

    @PostMapping("/log")
    public ResponseEntity<Void> logEvent(@Valid @RequestBody AuditLogRequest request) {
        auditService.logEvent(request);
        return ResponseEntity.accepted().build();
    }

    @GetMapping("/user/{userId}")
    public ResponseEntity<List<AuditLogResponse>> getLogsByUser(@PathVariable String userId, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsByUser(userId, page, size));
    }

    @GetMapping("/module/{moduleName}")
    public ResponseEntity<List<AuditLogResponse>> getLogsByModule(@PathVariable String moduleName, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsByModule(moduleName, page, size));
    }

    @GetMapping("/severity/{severity}")
    public ResponseEntity<List<AuditLogResponse>> getLogsBySeverity(@PathVariable AuditSeverity severity, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsBySeverity(severity, page, size));
    }

    @GetMapping("/range")
    public ResponseEntity<List<AuditLogResponse>> getLogsByRange(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime start,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime end, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsByTimeRange(start, end, page, size));
    }
}