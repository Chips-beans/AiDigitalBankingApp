package com.bank.digital_banking.module.audit.controller;

import com.bank.digital_banking.module.audit.dto.*;
import com.bank.digital_banking.module.audit.entity.AuditSeverity;
import com.bank.digital_banking.module.audit.service.AuditService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;

// ===================================================================
// Added for Swagger UI categorization & documentation: Audit Logs
// ===================================================================
@Tag(name = "Audit Logs", description = "Immutable audit log query and administrative security investigation")
@RestController
@RequestMapping("/api/v1/audit")
@RequiredArgsConstructor
public class AuditLogController {

    private final AuditService auditService;

    // Added: OpenAPI Operation description
    @Operation(summary = "Log audit event", description = "Asynchronously records an operational or security audit log entry")
    @PostMapping("/log")
    public ResponseEntity<Void> logEvent(@Valid @RequestBody AuditLogRequest request) {
        auditService.logEvent(request);
        return ResponseEntity.accepted().build();
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Get audit logs by user", description = "Retrieves audit trails for actions performed by or targeting a user")
    @GetMapping("/user/{userId}")
    public ResponseEntity<List<AuditLogResponse>> getLogsByUser(@PathVariable String userId, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsByUser(userId, page, size));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Get audit logs by module", description = "Retrieves audit entries filtered by module name (e.g. AUTH, ACCOUNT, TRANSACTION)")
    @GetMapping("/module/{moduleName}")
    public ResponseEntity<List<AuditLogResponse>> getLogsByModule(@PathVariable String moduleName, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsByModule(moduleName, page, size));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Get audit logs by severity", description = "Retrieves audit entries filtered by severity (INFO, WARN, ERROR, CRITICAL)")
    @GetMapping("/severity/{severity}")
    public ResponseEntity<List<AuditLogResponse>> getLogsBySeverity(@PathVariable AuditSeverity severity, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsBySeverity(severity, page, size));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Get audit logs by time range", description = "Retrieves audit entries within a specific ISO datetime range")
    @GetMapping("/range")
    public ResponseEntity<List<AuditLogResponse>> getLogsByRange(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime start,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime end, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(auditService.getLogsByTimeRange(start, end, page, size));
    }
}