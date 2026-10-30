package com.bank.digital_banking.module.ai.assistant;

import org.springframework.stereotype.Component;
import org.springframework.core.io.ClassPathResource;
import tools.jackson.databind.*;
import java.time.OffsetDateTime;
import java.util.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;

@Component
public class AssistantKnowledge {
    private final Map<String,JsonNode> topics=new LinkedHashMap<>();
    public AssistantKnowledge(ObjectMapper json) throws java.io.IOException {
        try(var in=new ClassPathResource("ai/kesor-help-v1.json").getInputStream()) {
            var data=json.readTree(in);
            if(data.path("version").asInt()!=1) throw new IllegalStateException("Unsupported help version");
            for(var topic:data.path("topics")) topics.put(topic.path("id").asText(),topic);
        }
    }
    public Set<String> topics() { return Collections.unmodifiableSet(topics.keySet()); }
    public Grounded answer(String topic,String locale,OffsetDateTime asOf) {
        var node=topics.get(topic);
        if(node==null) return new Grounded(new Answer(t(locale,"Which topic can I help with: accounts, transfers, receiving QR, scanning QR or PIN?","តើខ្ញុំអាចជួយអំពីគណនី ការផ្ទេរ ការទទួល QR ការស្កេន QR ឬ PIN?"),List.of(),asOf,"NOT_NEEDED"),Map.of(),Filters.empty());
        String target=node.path("target").asText();
        var actions="NONE".equals(target)?List.<Action>of():List.of(AssistantData.action("HELP_SCREEN",target,null,null,null));
        return new Grounded(new Answer(node.path(locale).asText(),List.of(new Card("HELP",t(locale,"Kesor help · v1","ជំនួយ Kesor · v1"),List.of(),actions)),asOf,"NOT_NEEDED"),Map.of(),Filters.empty());
    }
}
