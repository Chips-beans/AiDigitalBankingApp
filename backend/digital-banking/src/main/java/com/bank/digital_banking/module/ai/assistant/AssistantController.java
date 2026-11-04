package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.ai.adapter.AIProperties;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;

@io.swagger.v3.oas.annotations.tags.Tag(name="AI Assistant",description="Read-only, customer-owned banking conversations and recovery")
@RestController @RequestMapping("/api/v1/ai") @RequiredArgsConstructor
public class AssistantController {
    private final AssistantStore store;
    private final AssistantService service;
    private final AssistantProvider provider;
    private final AIProperties properties;
    private <T> ResponseEntity<ApiResponse<T>> ok(T value) { return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ApiResponse.success(value,"Assistant")); }
    @GetMapping("/capabilities") public ResponseEntity<?> capabilities() {
        return ok(Map.of("available",provider.available(),"capabilities",List.of("BALANCES","SEARCH","DETAIL","MONTHLY","TOTALS","COMPARE","HELP","GENERAL"),"locales",List.of("en","km"),"retentionDays",30,"maxMessageLength",2000,"minuteLimit",properties.getMinuteLimit(),"dailyLimit",properties.getDailyLimit()));
    }
    @GetMapping("/conversations") public ResponseEntity<ApiResponse<Page<Conversation>>> list(@AuthenticationPrincipal User user,@RequestParam(required=false) String cursor,@RequestParam(defaultValue="20") int size,@RequestParam(required=false) String requestKey) { return ok(requestKey==null?store.conversations(user.getId(),cursor,size):new Page<>(List.of(store.recoverCreation(user.getId(),requestKey)),null)); }
    @PostMapping("/conversations") public ResponseEntity<ApiResponse<Conversation>> create(@AuthenticationPrincipal User user,@RequestHeader("Idempotency-Key") String key) {
        return ResponseEntity.status(201).cacheControl(CacheControl.noStore()).body(ApiResponse.success(store.create(user.getId(),key),"Conversation created"));
    }
    @PatchMapping("/conversations/{id}") public ResponseEntity<ApiResponse<Conversation>> rename(@AuthenticationPrincipal User user,@PathVariable UUID id,@Valid @RequestBody Rename body) { return ok(store.rename(user.getId(),id,body.title())); }
    @DeleteMapping("/conversations/{id}") public ResponseEntity<?> delete(@AuthenticationPrincipal User user,@PathVariable UUID id) { store.delete(user.getId(),id);return ok(Map.of("deleted",true)); }
    @GetMapping("/conversations/{id}/messages") public ResponseEntity<ApiResponse<Page<Message>>> messages(@AuthenticationPrincipal User user,@PathVariable UUID id,@RequestParam(required=false) String cursor,@RequestParam(defaultValue="20") int size) { return ok(store.messages(user.getId(),id,cursor,size)); }
    @PostMapping("/conversations/{id}/messages") public ResponseEntity<ApiResponse<Turn>> send(@AuthenticationPrincipal User user,@PathVariable UUID id,@RequestHeader("Idempotency-Key") String key,@Valid @RequestBody Question body) {
        var result=service.submit(user,id,key,body);
        return ResponseEntity.status("PENDING".equals(result.status())?202:200).cacheControl(CacheControl.noStore()).body(ApiResponse.success(result,"Assistant request"));
    }
    @GetMapping("/conversations/{id}/requests/{key}") public ResponseEntity<ApiResponse<Turn>> status(@AuthenticationPrincipal User user,@PathVariable UUID id,@PathVariable String key) { return ok(store.status(user.getId(),id,key)); }
}
