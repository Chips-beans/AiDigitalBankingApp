package com.bank.digital_banking.module.ai.assistant;

import jakarta.validation.constraints.*;
import java.time.OffsetDateTime;
import java.util.*;

public final class AssistantModels {
    private AssistantModels() {}
    public enum Capability { BALANCES, SEARCH, DETAIL, MONTHLY, TOTALS, COMPARE, HELP, GENERAL, CLARIFY, UNSUPPORTED }
    public record Filters(String currency, String accountNumber, String month, String from, String to,
                          String amount, String direction, String type, String status, String reference) {
        public static Filters empty() { return new Filters(null,null,null,null,null,null,null,null,null,null); }
        public Filters inherit(Filters prior) {
            if(prior==null) return this;
            return new Filters(or(currency,prior.currency),or(accountNumber,prior.accountNumber),or(month,prior.month),
                    or(from,prior.from),or(to,prior.to),or(amount,prior.amount),or(direction,prior.direction),
                    or(type,prior.type),or(status,prior.status),or(reference,prior.reference));
        }
        private static String or(String a,String b) { return a==null?b:a; }
    }
    public record Question(@NotBlank @Size(max=2000) String message,
                           @NotNull @Pattern(regexp="en|km") String locale, Filters context) {}
    public record Rename(@NotBlank @Size(max=80) String title) {}
    /** {@code general} asks for general money guidance in addition to (or, for GENERAL, instead of) customer facts. */
    public record Intent(Capability capability, Filters filters, String topic, boolean followUp, boolean general) {
        public Intent(Capability capability, Filters filters, String topic, boolean followUp) { this(capability,filters,topic,followUp,capability==Capability.GENERAL); }
    }
    public record Field(String label, String value) {}
    public record Action(String type, String value, String accountNumber, String currency, String month,
                         Filters filters, String cursor) {}
    public record Card(String type, String title, List<Field> fields, List<Action> actions) {}
    /** {@code mode} is GENERAL or MIXED when the text includes general guidance; null for verified-data and help answers (including answers stored before this field existed). */
    public record Answer(String reply, List<Card> cards, OffsetDateTime asOf, String explanationStatus, String mode) {
        public Answer(String reply, List<Card> cards, OffsetDateTime asOf, String explanationStatus) { this(reply,cards,asOf,explanationStatus,null); }
    }
    public record Turn(UUID requestId, String status, Answer answer, String errorCode) {}
    public record Conversation(UUID id, String title, OffsetDateTime createdAt, OffsetDateTime updatedAt) {}
    public record Message(long id, String message, String locale, Answer answer, OffsetDateTime createdAt) {}
    public record Page<T>(List<T> items, String nextCursor) {}
    public record Posting(long id, String reference, String source, String destination, String ownedAccount,
                          String amount, String fee, String currency, String type, String status,
                          String direction, boolean testFunding, OffsetDateTime createdAt) {}
    public record SearchPage(List<Posting> items, String nextCursor, Filters filters) {}
    public record Grounded(Answer answer, Map<String,String> facts, Filters filters) {}
    public static String t(String locale,String en,String km) { return "km".equals(locale)?km:en; }
}
