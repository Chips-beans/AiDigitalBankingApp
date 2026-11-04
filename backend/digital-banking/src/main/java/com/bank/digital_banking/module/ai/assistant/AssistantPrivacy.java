package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.common.exception.ApiException;
import org.springframework.http.HttpStatus;
import java.util.*;
import java.util.regex.*;

public final class AssistantPrivacy {
    private AssistantPrivacy() {}
    public static void rejectSecrets(String value) {
        if(value==null || value.isBlank() || value.length()>2000) throw AssistantSupport.invalid();
        if(Pattern.compile("(?iu)(?:\\b(?:pin|otp|passcode)|លេខ\\s*(?:PIN|OTP))\\s*(?:is|:|=)?\\s*[0-9០-៩]{4,8}\\b|\\b(?:password|secret|token)\\s*(?:is|:|=)\\s*\\S+|\\bBearer\\s+[A-Za-z0-9._-]+|eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]+\\.").matcher(value).find())
            throw new ApiException(HttpStatus.BAD_REQUEST,"AI_SENSITIVE_INPUT","Do not send PINs, OTPs, passwords or authentication tokens.");
    }
    public record Prepared(String text,Map<String,String> aliases) {
        public String resolve(String value) { return value==null?null:aliases.getOrDefault(value,value); }
    }
    /** Question text with the same redaction as {@link #prepare}, without the reference footer. */
    public static String sanitize(User user,String input) {
        String text=prepare(user,input,List.of()).text();
        int footer=text.lastIndexOf("\nPreviously displayed references in order:");
        return footer<0?text:text.substring(0,footer);
    }
    public static Prepared prepare(User user,String input,List<String> references) {
        var aliases=new LinkedHashMap<String,String>(); String text=input;
        var known=new ArrayList<String>();
        if(user.getEmail()!=null) known.add(user.getEmail());
        if(user.getUsername()!=null) known.add(user.getUsername());
        if(user.getFirstName()!=null) known.add(user.getFirstName());
        if(user.getLastName()!=null) known.add(user.getLastName());
        for(String name:known) if(name.length()>=3) text=text.replaceAll("(?iu)"+Pattern.quote(name),"[private]");
        text=text.replaceAll("(?iu)[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}","[email]")
                .replaceAll("https?://\\S+","[link]")
                .replaceAll("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+","[token]");
        for(String regex:List.of("\\bTXN[-_][A-Za-z0-9_-]+\\b","(?<![0-9])[0-9]{10,20}(?![0-9])")) {
            var matcher=Pattern.compile(regex).matcher(text);var result=new StringBuilder();
            while(matcher.find()) {
                String original=matcher.group();
                String alias=aliases.entrySet().stream().filter(e->e.getValue().equals(original)).map(Map.Entry::getKey).findFirst().orElse("record_"+aliases.size());
                aliases.put(alias,original); matcher.appendReplacement(result,alias);
            }
            matcher.appendTail(result);text=result.toString();
        }
        var referenceAliases=new ArrayList<String>();
        for(String ref:references.stream().limit(20).toList()) {
            String alias=aliases.entrySet().stream().filter(e->e.getValue().equals(ref)).map(Map.Entry::getKey).findFirst().orElse("record_"+aliases.size());
            aliases.put(alias,ref); referenceAliases.add(alias);
        }
        text=text.replaceAll("(?<![\\w])(?:\\+[0-9]|0[0-9])[0-9 ()-]{7,}[0-9](?![\\w])","[private-number]");
        if(text.length()>8000) text=text.substring(text.length()-8000);
        return new Prepared(text+"\nPreviously displayed references in order: "+referenceAliases,Map.copyOf(aliases));
    }
}
