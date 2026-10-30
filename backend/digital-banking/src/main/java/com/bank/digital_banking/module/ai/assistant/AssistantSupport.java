package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.common.exception.*;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;

public final class AssistantSupport {
    public static final ZoneId ZONE=ZoneId.of("Asia/Phnom_Penh");
    private AssistantSupport() {}
    public static ApiException invalid() { return new ApiException(HttpStatus.BAD_REQUEST,"INVALID_REQUEST","Check the assistant request"); }
    public static ApiException unavailable() { return new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"AI_UNAVAILABLE","The assistant is unavailable. Your banking services remain available."); }
    public static ApiException providerInvalid() { return new ApiException(HttpStatus.BAD_GATEWAY,"AI_INVALID_RESPONSE","The assistant could not verify its response. Try again."); }
    public static ResourceNotFoundException missing() { return new ResourceNotFoundException("Conversation or banking record unavailable"); }
    public static String key(String value) {
        if(value==null || !value.matches("[A-Za-z0-9_-]{8,100}")) throw invalid();
        return value;
    }
    public static int size(int n) { if(n<1 || n>50) throw invalid(); return n; }
    public static String hash(String value) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))); }
        catch(java.security.NoSuchAlgorithmException ex) { throw new IllegalStateException(ex); }
    }
    public static String encode(ObjectMapper json,Object value) { return json.writeValueAsString(value); }
    public static <T> T decode(ObjectMapper json,String value,Class<T> type) { return json.readValue(value,type); }
    public static String cursor(OffsetDateTime time,String id) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString((time+"|"+id).getBytes(StandardCharsets.UTF_8));
    }
    public record Boundary(OffsetDateTime time,String id) {}
    public static Boundary boundary(String value) {
        if(value==null || value.isBlank()) return null;
        try {
            if(value.length()>180) throw invalid();
            var parts=new String(Base64.getUrlDecoder().decode(value),StandardCharsets.UTF_8).split("\\|",-1);
            if(parts.length!=2) throw invalid();
            return new Boundary(OffsetDateTime.parse(parts[0]),parts[1]);
        } catch(RuntimeException ex) { throw invalid(); }
    }
    public static OffsetDateTime now(Clock clock) { return OffsetDateTime.now(clock).withOffsetSameInstant(ZoneOffset.UTC); }
}
