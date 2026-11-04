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
        boolean generalOnly=intent.capability()==Capability.GENERAL;
        Grounded grounded;
        if(generalOnly) {
            // No customer data is read or sent; earlier filters are kept so a later data follow-up still works.
            grounded=new Grounded(new Answer("",List.of(),OffsetDateTime.now(clock).withOffsetSameInstant(ZoneOffset.UTC),"NOT_NEEDED"),Map.of(),prior);
        } else {
            try { grounded=data.answer(user,new Intent(intent.capability(),f,intent.topic(),intent.followUp(),intent.general()),question.locale()); }
            catch(ApiException ex) { if("INVALID_REQUEST".equals(ex.getCode())) throw providerInvalid();throw ex; }
            catch(IllegalArgumentException ex) { throw providerInvalid(); }
        }
        if(!generalOnly && grounded.facts().isEmpty()) return grounded;
        boolean mixed=!generalOnly && intent.general();
        String mode=generalOnly?"GENERAL":mixed?"MIXED":"ACCOUNT";
        try {
            String text=render(provider.compose(AssistantPrivacy.sanitize(user,question.message()),grounded.facts(),mode,question.locale(),deadline),grounded.facts(),generalOnly,question.locale());
            String reply=generalOnly?text:grounded.answer().reply()+"\n\n"+text;
            if(generalOnly || mixed) reply+="\n\n"+disclaimer(question.locale());
            var answer=new Answer(reply,grounded.answer().cards(),grounded.answer().asOf(),"AI",generalOnly||mixed?mode:null);
            return new Grounded(answer,grounded.facts(),generalOnly?prior:grounded.filters());
        } catch(RuntimeException ex) {
            // Verified facts remain usable when the optional prose cannot be obtained/validated; a general answer has nothing else to show.
            if(generalOnly) throw ex instanceof ApiException?ex:providerInvalid();
            return new Grounded(new Answer(grounded.answer().reply(),grounded.answer().cards(),grounded.answer().asOf(),"FALLBACK"),grounded.facts(),grounded.filters());
        }
    }
    public static String disclaimer(String locale) {
        return t(locale,"General information only, not financial advice.","នេះជាព័ត៌មានទូទៅប៉ុណ្ណោះ មិនមែនជាដំបូន្មានហិរញ្ញវត្ថុទេ។");
    }
    private Intent parse(JsonNode node,AssistantPrivacy.Prepared prepared) {
        try {
            requireKeys(node,Set.of("capability","filters","topic","followUp","general"));
            var f=node.get("filters");
            requireKeys(f,Set.of("currency","accountNumber","month","from","to","amount","direction","type","status","reference"));
            if(!node.path("followUp").isBoolean() || !node.path("general").isBoolean() || !node.path("capability").isString()) throw providerInvalid();
            String account=optional(f,"accountNumber"),ref=optional(f,"reference");
            if(account!=null && !prepared.aliases().containsKey(account)) throw providerInvalid();
            if(ref!=null && !prepared.aliases().containsKey(ref)) throw providerInvalid();
            var filters=new Filters(optional(f,"currency"),prepared.resolve(account),optional(f,"month"),optional(f,"from"),optional(f,"to"),optional(f,"amount"),optional(f,"direction"),optional(f,"type"),optional(f,"status"),prepared.resolve(ref));
            String topic=optional(node,"topic");
            if(topic!=null && !Set.of("accounts","transfers","qr_receive","qr_scan","pin").contains(topic)) throw providerInvalid();
            return new Intent(Capability.valueOf(node.get("capability").asText()),filters,topic,node.get("followUp").asBoolean(),node.get("general").asBoolean());
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
    public static String renderExplanation(String template,Map<String,String> facts) { return render(template,facts,false); }
    private static final Pattern PLACEHOLDER=Pattern.compile("\\{\\{([A-Za-z0-9_]+)}}");
    private static final Pattern ALWAYS_BAD=Pattern.compile("[@{}]|https?://|www\\.|\\bTXN\\b|\\p{N}{6,}",Pattern.CASE_INSENSITIVE);
    // With customer facts every digit, currency word and statistic must come from a placeholder, so the model cannot restate or invent figures.
    private static final Pattern DATA_BAD=Pattern.compile("[\\p{N}%$៛]|\\b(?:USD|KHR|SUCCESS|FAILED|PENDING|REVERSED|percent|percentage|hundred|thousand|million|billion)\\b|ភាគរយ|ពាន់|ម៉ឺន|លាន",Pattern.CASE_INSENSITIVE);
    private static final Pattern CREDENTIAL=Pattern.compile("(?<![A-Za-z])(?:PIN|OTP|password|passcode|one-time code)(?![A-Za-z])|ពាក្យសម្ងាត់|លេខកូដសម្ងាត់",Pattern.CASE_INSENSITIVE);
    private static final Pattern NEGATION=Pattern.compile("(?<![A-Za-z])(?:never|not|don't|dont|do not|avoid|no one|nobody|cannot|can't|won't)(?![A-Za-z])|កុំ|មិន|ហាម|គ្មាន",Pattern.CASE_INSENSITIVE);
    // Handing a credential over: share/give/tell/... in English, ចែករំលែក/ផ្តល់/ប្រាប់/ផ្ញើ/បញ្ចូល/សុំ in Khmer.
    private static final Pattern HAND_OVER=Pattern.compile("(?<![A-Za-z])(?:share|give|tell|send|enter|type|read|provide|say|reveal|disclose|confirm|ask|request)(?![A-Za-z])|ចែករំលែក|ផ្តល់|ផ្ដល់|ប្រាប់|ផ្ញើ|បញ្ចូល|សុំ",Pattern.CASE_INSENSITIVE);
    private static final Pattern STATED_NUMBER=Pattern.compile("\\p{N}{3,}");
    private static final String LEAD="(?:^|[.!?។\\n]\\s*|\\bplease\\s+|\\byou\\s+(?:should|must|can|could|need\\s+to)\\s+)";
    // Moving money is only a directive when it goes to someone else: "transfer some to savings" and "pay yourself first" are ordinary tips.
    private static final Pattern DIRECTIVE=Pattern.compile(
            LEAD+"(?:send|transfer|wire|pay)\\b(?:[^.!?។\\n]{0,80}?\\b(?:to|into)\\s+(?:this|that|these|those|the|a|an|my|our|his|her|their|someone|anyone|us|them|him|me|account|number|\\p{N})\\b(?!\\s+(?:[\\p{L}-]+\\s+)?(?:savings|emergency|own)\\b)"
            +"|\\s+(?:money\\s+|funds\\s+|it\\s+)?(?:to\\s+)?(?:this|that|the\\s+following|the\\s+caller|us|them|him|her|someone|anyone|a\\s+stranger|the\\s+number|the\\s+agent|everything|all\\s+of\\s+it|(?:the|your|all\\s+(?:of\\s+)?your)\\s+(?:balance|money|funds|savings))\\b)"
            +"|"+LEAD+"(?:call|contact|message|email|text|visit)\\b(?!\\s+yourself\\b)"
            +"|(?:សូម|អ្នកគួរ|អ្នកត្រូវ)\\s*(?:ផ្ញើ|ផ្ទេរ|បង់(?:ប្រាក់)?ទៅ|ទូរស័ព្ទ|ទាក់ទង)",Pattern.CASE_INSENSITIVE);
    /**
     * A clause naming a credential is unsafe when it hands it over ("share your PIN") without a prohibition earlier in the same
     * clause ("never share your PIN"), or when it states a number for it. Safety advice such as "keep your PIN secret" is fine.
     */
    static boolean unsafeCredential(String clause) {
        if(!CREDENTIAL.matcher(clause).find()) return false;
        if(STATED_NUMBER.matcher(clause).find()) return true;
        var verb=HAND_OVER.matcher(clause);
        while(verb.find()) if(!NEGATION.matcher(clause.substring(0,verb.start())).find()) return true;
        return false;
    }
    /** Turns model text into customer text. {@code generalOnly} text (no customer facts) may use ordinary numbers but never placeholders. */
    public static String render(String template,Map<String,String> facts,boolean generalOnly) { return render(template,facts,generalOnly,null); }
    private static final Pattern KHMER=Pattern.compile("[\u1780-\u17FF\u19E0-\u19FF]"),LATIN=Pattern.compile("\\p{IsLatin}"),OTHER=Pattern.compile("[\\p{L}&&[^\\p{IsKhmer}]&&[^\\p{IsLatin}]]");
    /**
     * The answer must be written in the requested language: Khmer text must be mostly Khmer script (Latin terms such as PIN,
     * QR or Kesor are fine), English text must contain no Khmer, and neither may contain any other script (Thai, Chinese, ...).
     */
    public static void requireLanguage(String prose,String locale) {
        if(locale==null) return;
        int khmer=count(KHMER,prose),latin=count(LATIN,prose),other=count(OTHER,prose);
        if(other>0) throw providerInvalid();
        if("km".equals(locale) ? khmer==0 || khmer<2*latin : khmer>0) throw providerInvalid();
    }
    private static int count(Pattern pattern,String text) { var m=pattern.matcher(text);int n=0;while(m.find()) n++;return n; }
    public static String render(String template,Map<String,String> facts,boolean generalOnly,String locale) {
        if(template==null || template.isBlank() || template.length()>2500) throw providerInvalid();
        var matcher=PLACEHOLDER.matcher(template);var out=new StringBuilder();int count=0;
        while(matcher.find()) {
            String value=facts.get(matcher.group(1)); if(value==null) throw providerInvalid();
            matcher.appendReplacement(out,Matcher.quoteReplacement(value));count++;
        }
        matcher.appendTail(out);
        String prose=PLACEHOLDER.matcher(template).replaceAll(" ");
        if(generalOnly ? count>0 : count==0) throw providerInvalid();
        if(ALWAYS_BAD.matcher(prose).find() || !generalOnly && DATA_BAD.matcher(prose).find() || DIRECTIVE.matcher(prose).find()) throw providerInvalid();
        for(String clause:prose.split("[.!?។\\n,;:]+")) if(unsafeCredential(clause)) throw providerInvalid();
        requireLanguage(prose,locale);
        return out.toString();
    }
}
