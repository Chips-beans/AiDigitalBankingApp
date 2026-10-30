package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import java.util.*;
import tools.jackson.databind.ObjectMapper;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantSupport.*;

@Service @RequiredArgsConstructor
public class AssistantService {
    private final AssistantStore store;
    private final AssistantEngine engine;
    private final AssistantData data;
    private final ObjectMapper json;
    public Turn submit(User user,UUID conversation,String key,Question question) {
        AssistantPrivacy.rejectSecrets(question.message());
        if(!Set.of("en","km").contains(question.locale())) throw invalid();
        data.validateSelected(user,question.context());
        var claim=store.claim(user.getId(),conversation,key,hash(conversation+"|"+encode(json,question)));
        if(!claim.acquired()) return claim.turn();
        long started=System.nanoTime();String outcome="COMPLETED";
        try {
            var grounded=engine.answer(user,question,store.messages(user.getId(),conversation,null,6).items(),store.lastFilters(user.getId(),conversation));
            return store.finish(user.getId(),conversation,key,question,grounded,null);
        } catch(ApiException ex) {
            outcome=ex.getCode();store.finish(user.getId(),conversation,key,question,null,ex.getCode()); throw ex;
        } catch(com.bank.digital_banking.common.exception.ResourceNotFoundException ex) {
            outcome="RESOURCE_NOT_FOUND";store.finish(user.getId(),conversation,key,question,null,outcome);throw ex;
        } catch(RuntimeException ex) {
            outcome="AI_INVALID_RESPONSE"; store.finish(user.getId(),conversation,key,question,null,outcome);throw providerInvalid();
        } finally {
            org.slf4j.LoggerFactory.getLogger(getClass()).info("Assistant turn outcome={} durationMs={}",outcome,(System.nanoTime()-started)/1_000_000);
        }
    }
}
