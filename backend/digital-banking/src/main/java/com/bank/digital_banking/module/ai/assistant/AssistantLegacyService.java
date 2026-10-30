package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.ai.dto.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import java.time.*;
import java.util.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;

@Service @RequiredArgsConstructor
public class AssistantLegacyService {
    private final UserRepository users;
    private final AssistantStore store;
    private final AssistantEngine engine;
    private final Clock clock;
    public FinancialChatResponse chat(FinancialChatRequest request) {
        AssistantPrivacy.rejectSecrets(request.message());
        var user=users.findById(request.userId()).orElseThrow(AssistantSupport::missing);
        store.charge(user.getId());
        var result=engine.answer(user,new Question(request.message(),"en",null),List.of(),Filters.empty());
        return new FinancialChatResponse(result.answer().reply(),AssistantSupport.now(clock).toString());
    }
}
