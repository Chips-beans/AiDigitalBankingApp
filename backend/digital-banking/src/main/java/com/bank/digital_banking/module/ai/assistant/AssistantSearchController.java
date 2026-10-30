package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;

@RestController @RequiredArgsConstructor
public class AssistantSearchController {
    private final AssistantData data;
    @GetMapping("/api/v1/transactions/search")
    @io.swagger.v3.oas.annotations.Operation(summary="Search the authenticated customer's transactions with bounded filters and cursors")
    public ResponseEntity<?> search(@AuthenticationPrincipal User user,
            @RequestParam(required=false) String currency,@RequestParam(required=false) String accountNumber,
            @RequestParam(required=false) String month,@RequestParam(required=false) String from,@RequestParam(required=false) String to,
            @RequestParam(required=false) String amount,@RequestParam(required=false) String direction,@RequestParam(required=false) String type,
            @RequestParam(required=false) String status,@RequestParam(required=false) String reference,
            @RequestParam(required=false) String cursor,@RequestParam(defaultValue="20") int size,@RequestParam(defaultValue="en") String locale) {
        if(!java.util.Set.of("en","km").contains(locale)) throw AssistantSupport.invalid();
        var page=data.search(user,new Filters(currency,accountNumber,month,from,to,amount,direction,type,status,reference),cursor,size);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ApiResponse.success(java.util.Map.of("items",page.items(),"cards",data.postingCards(page.items(),locale),"filters",page.filters(),"nextCursor",page.nextCursor()==null?"":page.nextCursor()),"Transaction search"));
    }
}
