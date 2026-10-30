package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.common.exception.ApiException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import tools.jackson.databind.*;
import java.time.*;
import java.util.*;
import java.util.regex.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantSupport.*;

@Service @RequiredArgsConstructor
public class AssistantEngine {
    private final AssistantProvider provider;
    private final AssistantData data;
    private final ObjectMapper json;
    private final Clock clock;

    public Grounded answer(User user,Question question,List<Message> recent,Filters prior) {
        if(!provider.available()) throw unavailable();
        AssistantPrivacy.rejectSecrets(question.message()); data.validateSelected(user,question.context());
        long deadline=System.nanoTime()+Duration.ofSeconds(25).toNanos();
        var history=new StringBuilder();var refs=new ArrayList<String>();
        for(var message:recent.stream().limit(6).toList().reversed()) history.append("Earlier customer question: ").append(message.message()).append('\n');
        if(!recent.isEmpty()) for(var card:recent.getFirst().answer().cards()) for(var action:card.actions()) if("TRANSACTION".equals(action.type())) refs.add(action.value());
        history.append("Validated prior filters: ").append(encode(json,prior));
        history.append("\nSelected context: ").append(encode(json,question.context()));
        history.append("\nCurrent customer question: ").append(question.message());
        var prepared=AssistantPrivacy.prepare(user,history.toString(),refs);
        String bankContext="Bank date: "+LocalDate.now(clock.withZone(ZONE))+"; zone: "+ZONE+"; response locale: "+question.locale()+"\n";
        Intent intent=parse(provider.classify(bankContext+prepared.text(),deadline),prepared);
        var base=intent.followUp()?prior:Filters.empty();
        if(question.context()!=null) base=question.context().inherit(base);
        var f=intent.filters();
        // A new month replaces old explicit search dates instead of silently reusing an older range.
        if(f.month()!=null && !Objects.equals(f.month(),base.month())) base=new Filters(base.currency(),base.accountNumber(),null,null,null,base.amount(),base.direction(),base.type(),base.status(),base.reference());
        f=f.inherit(base);
        if("ALL".equals(f.currency())) f=new Filters(null,f.accountNumber(),f.month(),f.from(),f.to(),f.amount(),f.direction(),f.type(),f.status(),f.reference());
        Grounded grounded;
        try { grounded=data.answer(user,new Intent(intent.capability(),f,intent.topic(),intent.followUp()),question.locale()); }
        catch(ApiException ex) { if("INVALID_REQUEST".equals(ex.getCode())) throw providerInvalid();throw ex; }
        catch(IllegalArgumentException ex) { throw providerInvalid(); }
        if(grounded.facts().isEmpty()) return grounded;
        try {
            String text=renderExplanation(provider.explain(grounded.facts(),question.locale(),deadline),grounded.facts());
            return new Grounded(new Answer(grounded.answer().reply()+"\n\n"+text,grounded.answer().cards(),grounded.answer().asOf(),"AI"),grounded.facts(),grounded.filters());
        } catch(RuntimeException ex) {
            // Verified facts remain usable when the optional prose cannot be obtained/validated.
            return new Grounded(new Answer(grounded.answer().reply(),grounded.answer().cards(),grounded.answer().asOf(),"FALLBACK"),grounded.facts(),grounded.filters());
        }
    }
    private Intent parse(JsonNode node,AssistantPrivacy.Prepared prepared) {
        try {
            requireKeys(node,Set.of("capability","filters","topic","followUp"));
            var f=node.get("filters");
            requireKeys(f,Set.of("currency","accountNumber","month","from","to","amount","direction","type","status","reference"));
            if(!node.path("followUp").isBoolean() || !node.path("capability").isString()) throw providerInvalid();
            String account=optional(f,"accountNumber"),ref=optional(f,"reference");
            if(account!=null && !prepared.aliases().containsKey(account)) throw providerInvalid();
            if(ref!=null && !prepared.aliases().containsKey(ref)) throw providerInvalid();
            var filters=new Filters(optional(f,"currency"),prepared.resolve(account),optional(f,"month"),optional(f,"from"),optional(f,"to"),optional(f,"amount"),optional(f,"direction"),optional(f,"type"),optional(f,"status"),prepared.resolve(ref));
            String topic=optional(node,"topic");
            if(topic!=null && !Set.of("accounts","transfers","qr_receive","qr_scan","pin").contains(topic)) throw providerInvalid();
            return new Intent(Capability.valueOf(node.get("capability").asText()),filters,topic,node.get("followUp").asBoolean());
        } catch(RuntimeException ex) { throw providerInvalid(); }
    }
    private void requireKeys(JsonNode node,Set<String> keys) {
        if(node==null || !node.isObject() || node.size()!=keys.size()) throw providerInvalid();
        for(String name:node.propertyNames()) if(!keys.contains(name)) throw providerInvalid();
    }
    private String optional(JsonNode node,String key) {
        var value=node.get(key); if(value==null || value.isNull()) return null;
        if(!value.isString() || value.asText().isBlank() || value.asText().length()>100) throw providerInvalid();
        return value.asText();
    }
    public static String renderExplanation(String template,Map<String,String> facts) {
        if(template==null || template.isBlank() || template.length()>1500) throw providerInvalid();
        var pattern=Pattern.compile("\\{\\{([A-Za-z0-9_]+)}}");
        var matcher=pattern.matcher(template);var out=new StringBuilder();int count=0;
        while(matcher.find()) {
            String value=facts.get(matcher.group(1)); if(value==null) throw providerInvalid();
            matcher.appendReplacement(out,Matcher.quoteReplacement(value));count++;
        }
        matcher.appendTail(out);
        String prose=pattern.matcher(template).replaceAll("");
        if(count==0 || Pattern.compile("[\\p{N}@{}]|https?://|\\b(?:USD|KHR|SUCCESS|FAILED|PENDING|TXN|PIN|OTP)\\b",Pattern.CASE_INSENSITIVE).matcher(prose).find()) throw providerInvalid();
        return out.toString();
    }
}
