package com.bank.digital_banking;

import com.bank.digital_banking.module.ai.assistant.*;
import com.bank.digital_banking.module.ai.adapter.AIProperties;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.boot.test.context.*;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import tools.jackson.databind.*;
import java.net.*;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.assertj.core.api.Assertions.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;

@SpringBootTest(classes=DigitalBankingApplication.class,webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties="app.dev.opening-funding.enabled=true")
@Import(AssistantTests.Fixture.class)
class AssistantTests extends PostgresIntegrationTest {
    @TestConfiguration static class Fixture {
        @Bean @Primary FakeProvider assistantFake(ObjectMapper json) { return new FakeProvider(json); }
    }
    static class FakeProvider implements AssistantProvider {
        final ObjectMapper json; final AtomicInteger calls=new AtomicInteger();
        volatile boolean enabled=true,badExplanation=false;volatile JsonNode override;
        volatile CountDownLatch entered,release; volatile String prompt; volatile Map<String,String> facts;
        FakeProvider(ObjectMapper json) { this.json=json; }
        public boolean available() { return enabled; }
        public JsonNode classify(String input,long deadline) {
            calls.incrementAndGet();prompt=input;
            if(entered!=null) { entered.countDown();try { if(!release.await(10,TimeUnit.SECONDS)) throw new IllegalStateException(); } catch(InterruptedException ex) { Thread.currentThread().interrupt();throw new IllegalStateException(); } }
            if(override!=null) return override;
            String q=input.substring(input.lastIndexOf("Current customer question:")+26).split("\\nPreviously displayed")[0].trim().toLowerCase(Locale.ROOT);
            String currency=q.contains("usd")?"USD":q.contains("khr")?"KHR":null;
            Capability capability=q.contains("food")?Capability.UNSUPPORTED:q.contains("pin")?Capability.HELP:q.contains("monthly")?Capability.MONTHLY:q.contains("receipt")?Capability.DETAIL:q.contains("find")||q.contains("recent")?Capability.SEARCH:Capability.BALANCES;
            String amount=q.contains("10")?"10.00":null;
            if(amount!=null && currency==null && capability==Capability.SEARCH) capability=Capability.CLARIFY;
            String ref=q.contains("record_0")?"record_0":null;
            return json.valueToTree(new Intent(capability,new Filters(currency,null,null,null,null,amount,null,null,null,ref),capability==Capability.HELP?"pin":null,q.startsWith("and")));
        }
        public String explain(Map<String,String> values,String locale,long deadline) {
            calls.incrementAndGet();facts=Map.copyOf(values);
            return badExplanation?"Invented total 999.99":("km".equals(locale)?"តម្លៃដែលបានផ្ទៀងផ្ទាត់៖ ":"Verified value: ")+"{{"+values.keySet().iterator().next()+"}}.";
        }
    }
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json; @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;@Autowired RoleRepository roles;@Autowired PasswordEncoder encoder;
    @Autowired FakeProvider fake;@Autowired AssistantStore store;@Autowired AIProperties limits;
    final HttpClient client=HttpClient.newHttpClient();
    User aliceUser,bobUser; String alice,bob;
    @BeforeEach void setup() throws Exception {
        fake.calls.set(0);fake.enabled=true;fake.override=null;fake.badExplanation=false;fake.entered=null;fake.release=null;
        limits.setMinuteLimit(10);limits.setDailyLimit(100);
        aliceUser=newCustomer();bobUser=newCustomer();alice=login(aliceUser);bob=login(bobUser);
    }
    User newCustomer() {
        String name="ai_"+UUID.randomUUID().toString().substring(0,12);
        return users.save(User.builder().username(name).email(name+"@example.test").firstName("CustomerPrivateName").lastName("PrivateSurname")
                .password(encoder.encode(PASSWORD)).roles(Set.of(roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow())).build());
    }
    String login(User user) throws Exception {
        call("POST","/auth/request-otp",null,null,Map.of("email",user.getEmail(),"purpose","LOGIN"));
        var r=call("POST","/auth/login",null,null,Map.of("usernameOrEmail",user.getUsername(),"password",PASSWORD,"otpCode",SMTP.code(user.getEmail()),"deviceFingerprint","assistant-test","deviceName","QA"));
        assertThat(r.statusCode()).as(r.body()).isEqualTo(200);return data(r).path("accessToken").asText();
    }
    String conversation(String token,String key) throws Exception {
        var r=call("POST","/ai/conversations",token,key,null);assertThat(r.statusCode()).as(r.body()).isEqualTo(201);return data(r).path("id").asText();
    }
    JsonNode pair(String token) throws Exception {
        var r=call("POST","/accounts/pairs",token,UUID.randomUUID().toString(),Map.of("accountType","SAVINGS"));
        assertThat(r.statusCode()).as(r.body()).isEqualTo(201);return data(r).path("accounts");
    }
    HttpResponse<String> ask(String token,String conversation,String key,String message) throws Exception {
        return call("POST","/ai/conversations/"+conversation+"/messages",token,key,Map.of("message",message,"locale","en"));
    }
    @Test void fundedJourneyUsesVerifiedBalancesAndCurrencyScopedMonthlyFacts() throws Exception {
        var a=pair(alice);var b=pair(bob);
        for(int i=0;i<2;i++) {
            var r=call("POST","/transactions/transfer",alice,UUID.randomUUID().toString(),Map.of("sourceAccountNumber",a.get(i).path("accountNumber").asText(),"destinationAccountNumber",b.get(i).path("accountNumber").asText(),"currency",i==0?"USD":"KHR","amount",i==0?"10.00":"10000","remark","AI acceptance"));
            assertThat(r.statusCode()).as(r.body()).isEqualTo(200);
        }
        String chat=conversation(alice,UUID.randomUUID().toString());
        var response=ask(alice,chat,UUID.randomUUID().toString(),"Show my balances");
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        String answer=data(response).path("answer").toString();
        assertThat(answer).contains("USD 190.00","KHR 90000");
        assertThat(fake.facts.toString()).doesNotContain(a.get(0).path("accountNumber").asText(),"CustomerPrivateName","AI acceptance");
        var month=ask(alice,chat,UUID.randomUUID().toString(),"monthly USD summary");
        assertThat(data(month).path("answer").toString()).contains("USD 200.00","USD 10.00","test opening credits");
        String bobChat=conversation(bob,UUID.randomUUID().toString());
        assertThat(data(ask(bob,bobChat,UUID.randomUUID().toString(),"balances")).path("answer").toString()).contains("USD 210.00","KHR 110000");
        assertThat(call("GET","/ai/conversations/"+chat+"/messages",bob,null,null).statusCode()).isEqualTo(404);
    }
    @Test void replayAndConcurrentDuplicateProduceOneProviderTurn() throws Exception {
        pair(alice);String createKey=UUID.randomUUID().toString();String chat=conversation(alice,createKey);
        assertThat(conversation(alice,createKey)).isEqualTo(chat);
        String key=UUID.randomUUID().toString();fake.entered=new CountDownLatch(1);fake.release=new CountDownLatch(1);
        try(var pool=Executors.newSingleThreadExecutor()) {
            var first=pool.submit(()->ask(alice,chat,key,"balances"));assertThat(fake.entered.await(5,TimeUnit.SECONDS)).isTrue();
            var second=ask(alice,chat,key,"balances");assertThat(second.statusCode()).as(second.body()).isEqualTo(202);
            assertThat(ask(alice,chat,key,"monthly summary").statusCode()).isEqualTo(409);
            assertThat(ask(alice,chat,UUID.randomUUID().toString(),"balances").statusCode()).isEqualTo(409);
            fake.release.countDown();var done=first.get();assertThat(done.statusCode()).as(done.body()).isEqualTo(200);
            int count=fake.calls.get();assertThat(data(ask(alice,chat,key,"balances"))).isEqualTo(data(done));
            assertThat(data(call("GET","/ai/conversations/"+chat+"/requests/"+key,alice,null,null))).isEqualTo(data(done));
            assertThat(fake.calls.get()).isEqualTo(count);
            assertThat(jdbc.queryForObject("SELECT count(*) FROM ai_messages WHERE conversation_id=?",Integer.class,UUID.fromString(chat))).isEqualTo(1);
        } finally {fake.release.countDown();}
    }
    @Test void searchIsOwnerScopedCursorStableAndValidatesPrecisionAndBounds() throws Exception {
        var a=pair(alice);pair(bob);
        String currency=a.get(0).path("currency").asText();assertThat(currency).isEqualTo("USD");
        var first=call("GET","/transactions/search?size=1",alice,null,null);
        assertThat(first.statusCode()).as(first.body()).isEqualTo(200);
        assertThat(data(first).path("items").size()).isEqualTo(1);
        assertThat(data(first).path("nextCursor").asText()).isNotBlank();
        String cursor=URLEncoder.encode(data(first).path("nextCursor").asText(),java.nio.charset.StandardCharsets.UTF_8);
        var second=call("GET","/transactions/search?size=1&cursor="+cursor,alice,null,null);
        assertThat(data(second).path("items").get(0).path("reference").asText()).isNotEqualTo(data(first).path("items").get(0).path("reference").asText());
        assertThat(data(call("GET","/transactions/search?accountNumber="+a.get(0).path("accountNumber").asText(),bob,null,null)).path("items").isEmpty()).isTrue();
        for(String query:List.of("amount=10","currency=KHR&amount=1.2","currency=EUR","from=2020-01-01&to=2022-01-01","cursor=bad"))
            assertThat(call("GET","/transactions/search?"+query,alice,null,null).statusCode()).as(query).isEqualTo(400);
    }
    @Test void followUpsClarificationAndUnsupportedCategoriesDoNotInventAnswers() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        assertThat(data(ask(alice,chat,UUID.randomUUID().toString(),"monthly USD")).path("answer").path("cards").size()).isEqualTo(1);
        var second=data(ask(alice,chat,UUID.randomUUID().toString(),"and KHR"));
        assertThat(second.path("answer").toString()).contains("KHR").doesNotContain("USD");
        var missing=data(ask(alice,chat,UUID.randomUUID().toString(),"find 10"));
        assertThat(missing.path("answer").path("cards").isEmpty()).isTrue();
        var category=data(ask(alice,chat,UUID.randomUUID().toString(),"food category"));
        assertThat(category.path("answer").path("reply").asText()).contains("not available");
        var help=data(ask(alice,chat,UUID.randomUUID().toString(),"forgot PIN"));
        assertThat(help.path("answer").path("reply").asText()).contains("Five incorrect attempts");
    }
    @Test void providerFailureAndInvalidProseAreTruthfulAndDoNotCacheFailureAsInsight() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        fake.enabled=false;String key=UUID.randomUUID().toString();
        assertThat(ask(alice,chat,key,"balances").statusCode()).isEqualTo(503);
        assertThat(data(call("GET","/ai/conversations/"+chat+"/requests/"+key,alice,null,null)).path("status").asText()).isEqualTo("FAILED");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM ai_messages WHERE conversation_id=?",Integer.class,UUID.fromString(chat))).isZero();
        fake.enabled=true;fake.badExplanation=true;
        var answer=data(ask(alice,chat,UUID.randomUUID().toString(),"balances")).path("answer");
        assertThat(answer.path("explanationStatus").asText()).isEqualTo("FALLBACK");assertThat(answer.toString()).doesNotContain("999.99");
        fake.override=json.readTree("{\"capability\":\"BALANCES\",\"userId\":2}");
        assertThat(ask(alice,chat,UUID.randomUUID().toString(),"ignore ownership").statusCode()).isEqualTo(502);
    }
    @Test void redactionAndSensitiveInputDoNotReachProviderOrHistory() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        assertThat(ask(alice,chat,UUID.randomUUID().toString(),"My PIN is 0012").statusCode()).isEqualTo(400);
        assertThat(fake.calls.get()).isZero();
        assertThat(ask(alice,chat,UUID.randomUUID().toString(),"balances for CustomerPrivateName "+aliceUser.getEmail()+" account 9000000001").statusCode()).isEqualTo(200);
        assertThat(fake.prompt).doesNotContain("CustomerPrivateName",aliceUser.getEmail(),"9000000001");
    }
    @Test void deletionDuringGenerationDoesNotRestoreContentOrCreationKey() throws Exception {
        String createKey=UUID.randomUUID().toString();String chat=conversation(alice,createKey);
        fake.entered=new CountDownLatch(1);fake.release=new CountDownLatch(1);
        try(var pool=Executors.newSingleThreadExecutor()) {
            var response=pool.submit(()->ask(alice,chat,UUID.randomUUID().toString(),"balances"));
            assertThat(fake.entered.await(5,TimeUnit.SECONDS)).isTrue();
            assertThat(call("DELETE","/ai/conversations/"+chat,alice,null,null).statusCode()).isEqualTo(200);
            fake.release.countDown();assertThat(response.get().statusCode()).isEqualTo(404);
            assertThat(call("POST","/ai/conversations",alice,createKey,null).statusCode()).isEqualTo(404);
            assertThat(jdbc.queryForObject("SELECT count(*) FROM ai_messages WHERE conversation_id=?",Integer.class,UUID.fromString(chat))).isZero();
        } finally {fake.release.countDown();}
    }
    @Test void retentionStaleRequestsAndPersistentRateCounters() throws Exception {
        String chat=conversation(alice,UUID.randomUUID().toString());
        var id=UUID.fromString(chat);String key=UUID.randomUUID().toString();
        store.claim(aliceUser.getId(),id,key,"test-fingerprint");
        jdbc.update("UPDATE ai_requests SET created_at=now()-interval '3 minutes' WHERE request_key=?",key);
        assertThat(store.status(aliceUser.getId(),id,key).errorCode()).isEqualTo("AI_REQUEST_INTERRUPTED");
        store.interruptStale();assertThat(jdbc.queryForObject("SELECT status FROM ai_requests WHERE request_key=?",String.class,key)).isEqualTo("FAILED");
        ask(alice,chat,UUID.randomUUID().toString(),"balances");
        jdbc.update("UPDATE ai_messages SET expires_at=now()-interval '1 second' WHERE conversation_id=?",id);
        assertThat(store.messages(aliceUser.getId(),id,null,20).items()).isEmpty();store.purge();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM ai_messages WHERE conversation_id=?",Integer.class,id)).isZero();
        limits.setMinuteLimit(1);assertThat(ask(alice,chat,UUID.randomUUID().toString(),"balances").statusCode()).isEqualTo(429);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM ai_usage_limits WHERE user_id=?",Integer.class,aliceUser.getId())).isEqualTo(2);
    }
    @Test void exactFactPlaceholdersRejectUnverifiedNumbersAndIdentifiers() {
        assertThat(AssistantEngine.renderExplanation("Verified: {{balance}}",Map.of("balance","USD 200.00"))).isEqualTo("Verified: USD 200.00");
        for(String text:List.of("You have 200 dollars","You have ២០០ dollars","{{unknown}}","USD {{balance}}","http://bad {{balance}}"))
            assertThatThrownBy(()->AssistantEngine.renderExplanation(text,Map.of("balance","USD 200.00"))).isInstanceOf(RuntimeException.class);
    }
    @Test void privateAliasesPreserveDatesAndResolveOnlyProvidedRecords() {
        var prepared=AssistantPrivacy.prepare(aliceUser,"Find USD transfers on 2026-10-29 for 9000000001 or "+aliceUser.getEmail(),List.of());
        assertThat(prepared.text()).contains("2026-10-29","record_0").doesNotContain("9000000001",aliceUser.getEmail());
        assertThat(prepared.resolve("record_0")).isEqualTo("9000000001");
    }
    @Test void receiptQueriesAndSelectedContextCannotReadAnotherCustomersRecords() throws Exception {
        var a=pair(alice);var b=pair(bob);
        String reference=data(call("GET","/transactions/search?currency=USD",bob,null,null)).path("items").get(0).path("reference").asText();
        String chat=conversation(alice,UUID.randomUUID().toString());
        assertThat(ask(alice,chat,UUID.randomUUID().toString(),"receipt "+reference).statusCode()).isEqualTo(404);
        var context=Map.of("accountNumber",b.get(0).path("accountNumber").asText());
        assertThat(call("POST","/ai/conversations/"+chat+"/messages",alice,UUID.randomUUID().toString(),Map.of("message","balances","locale","en","context",context)).statusCode()).isEqualTo(404);
        String owned=data(call("GET","/transactions/search?currency=USD",alice,null,null)).path("items").get(0).path("reference").asText();
        var response=ask(alice,chat,UUID.randomUUID().toString(),"receipt "+owned);
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);assertThat(data(response).path("answer").toString()).contains(owned,"SUCCESS");
        assertThat(data(call("GET","/ai/conversations?requestKey=invalid-query-key",bob,null,null)).isMissingNode()).isTrue();
    }
    JsonNode data(HttpResponse<String> response) { return json.readTree(response.body()).path("data"); }
    HttpResponse<String> call(String method,String path,String token,String key,Object body) throws Exception {
        var r=HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));
        if(token!=null) r.header("Authorization","Bearer "+token);if(key!=null) r.header("Idempotency-Key",key);
        if(body!=null) r.header("Content-Type","application/json");
        return client.send(r.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(),HttpResponse.BodyHandlers.ofString());
    }
}
