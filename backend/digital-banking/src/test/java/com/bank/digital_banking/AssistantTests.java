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
        volatile boolean enabled=true,badExplanation=false;volatile JsonNode override;volatile String composeOverride,lastMode,lastQuestion;
        volatile CountDownLatch entered,release; volatile String prompt; volatile Map<String,String> facts;
        FakeProvider(ObjectMapper json) { this.json=json; }
        public boolean available() { return enabled; }
        public JsonNode classify(String input,long deadline) {
            calls.incrementAndGet();prompt=input;
            if(entered!=null) { entered.countDown();try { if(!release.await(10,TimeUnit.SECONDS)) throw new IllegalStateException(); } catch(InterruptedException ex) { Thread.currentThread().interrupt();throw new IllegalStateException(); } }
            if(override!=null) return override;
            String q=input.substring(input.lastIndexOf("Current customer question:")+26).split("\\nPreviously displayed")[0].trim().toLowerCase(Locale.ROOT);
            String currency=q.contains("usd")?"USD":q.contains("khr")?"KHR":null;
            Capability capability=q.contains("stock")||q.contains("food")?Capability.UNSUPPORTED:q.contains("inflation")?Capability.GENERAL:q.contains("compare")?Capability.COMPARE:q.contains("totals")?Capability.TOTALS:q.contains("pin")?Capability.HELP:q.contains("monthly")?Capability.MONTHLY:q.contains("receipt")?Capability.DETAIL:q.contains("find")||q.contains("recent")?Capability.SEARCH:Capability.BALANCES;
            String amount=q.contains("10")?"10.00":null;
            if(amount!=null && currency==null && capability==Capability.SEARCH) capability=Capability.CLARIFY;
            String ref=q.contains("record_0")?"record_0":null;
            return json.valueToTree(new Intent(capability,new Filters(currency,null,null,null,null,amount,null,null,null,ref),capability==Capability.HELP?"pin":null,q.startsWith("and"),capability==Capability.GENERAL||q.contains("tips")));
        }
        public String compose(String question,Map<String,String> values,String mode,String locale,long deadline) {
            calls.incrementAndGet();facts=Map.copyOf(values);lastMode=mode;lastQuestion=question;
            if(composeOverride!=null) return composeOverride;
            if(badExplanation) return "Invented total 999.99";
            if("GENERAL".equals(mode)) return "km".equals(locale)?"មូលនិធិសង្គ្រោះបន្ទាន់ជួយអ្នកពេលមានការចំណាយមិនបានរំពឹង។":"A small emergency fund helps when expenses are unexpected.";
            String fact="{{"+values.keySet().iterator().next()+"}}";
            if("MIXED".equals(mode)) return "Verified value: "+fact+". Keeping a small buffer is a sensible habit.";
            return ("km".equals(locale)?"តម្លៃដែលបានផ្ទៀងផ្ទាត់៖ ":"Verified value: ")+fact+".";
        }
    }
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json; @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;@Autowired RoleRepository roles;@Autowired PasswordEncoder encoder;
    @Autowired FakeProvider fake;@Autowired AssistantStore store;@Autowired AIProperties limits;
    final HttpClient client=HttpClient.newHttpClient();
    User aliceUser,bobUser; String alice,bob;
    @BeforeEach void setup() throws Exception {
        fake.calls.set(0);fake.enabled=true;fake.override=null;fake.badExplanation=false;fake.composeOverride=null;fake.lastMode=null;fake.lastQuestion=null;fake.entered=null;fake.release=null;
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
    @Test void generalQuestionsNeedNoCustomerDataAndCarryTheDisclaimer() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        var response=ask(alice,chat,UUID.randomUUID().toString(),"explain inflation CustomerPrivateName "+aliceUser.getEmail());
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        var answer=data(response).path("answer");
        assertThat(answer.path("mode").asText()).isEqualTo("GENERAL");assertThat(answer.path("explanationStatus").asText()).isEqualTo("AI");
        assertThat(answer.path("cards").isEmpty()).isTrue();
        assertThat(answer.path("reply").asText()).contains("emergency fund","not financial advice");
        assertThat(fake.facts).isEmpty();assertThat(fake.lastMode).isEqualTo("GENERAL");
        assertThat(fake.lastQuestion).doesNotContain("CustomerPrivateName",aliceUser.getEmail());
        assertThat(data(call("GET","/ai/conversations/"+chat+"/messages",alice,null,null)).path("items").get(0).path("answer").path("mode").asText()).isEqualTo("GENERAL");
        // Answers stored before the mode field existed still load, with no mode.
        jdbc.update("UPDATE ai_messages SET answer_json=(answer_json::jsonb - 'mode')::text WHERE conversation_id=?",UUID.fromString(chat));
        assertThat(store.messages(aliceUser.getId(),UUID.fromString(chat),null,20).items().getFirst().answer().mode()).isNull();
    }
    @Test void accountQuestionsWithTipsKeepVerifiedCardsAndLabelTheGeneralPart() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        var answer=data(ask(alice,chat,UUID.randomUUID().toString(),"balances with tips")).path("answer");
        assertThat(answer.path("mode").asText()).isEqualTo("MIXED");assertThat(answer.path("cards").size()).isEqualTo(2);
        assertThat(answer.path("reply").asText()).contains("USD 200.00","small buffer","not financial advice");
        assertThat(fake.lastMode).isEqualTo("MIXED");
        var plain=data(ask(alice,chat,UUID.randomUUID().toString(),"balances")).path("answer");
        assertThat(plain.path("mode").isNull()).isTrue();assertThat(plain.path("reply").asText()).doesNotContain("not financial advice");
    }
    @Test void fabricatedFiguresAndUnsafeGeneralTextNeverReachTheCustomer() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        for(String bad:List.of("You spent 999 this month, {{USD_balance}}","You spent ៩៩៩ this month, {{USD_balance}}","Balance is up fifty percent, {{USD_balance}}","Plenty of room, {{USD_balance}} and 40% more")) {
            fake.composeOverride=bad;
            var answer=data(ask(alice,chat,UUID.randomUUID().toString(),"balances with tips")).path("answer");
            assertThat(answer.path("explanationStatus").asText()).as(bad).isEqualTo("FALLBACK");
            assertThat(answer.path("cards").size()).isEqualTo(2);assertThat(answer.path("mode").isNull()).isTrue();
            assertThat(answer.path("reply").asText()).doesNotContain("999","៩៩៩","percent","40%");
        }
        for(String bad:List.of("Open https://example.test to claim it.","Please send money to this account.","Share your PIN with support.","Your balance is {{USD_balance}}.","Call 012345678901 today.")) {
            fake.composeOverride=bad;
            assertThat(ask(alice,chat,UUID.randomUUID().toString(),"explain inflation").statusCode()).as(bad).isEqualTo(502);
        }
        assertThat(jdbc.queryForObject("SELECT count(*) FROM ai_messages WHERE conversation_id=?",Integer.class,UUID.fromString(chat))).isEqualTo(4);
    }
    @Test void specificProductAdviceIsRefusedWithoutAComposeCall() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        var answer=data(ask(alice,chat,UUID.randomUUID().toString(),"which stock should I buy")).path("answer");
        assertThat(answer.path("reply").asText()).contains("not available");assertThat(answer.path("cards").isEmpty()).isTrue();
        assertThat(fake.calls.get()).isEqualTo(1);
    }
    @Test void totalsAndComparisonUseTheSameFiguresAsMonthlyAnalytics() throws Exception {
        var a=pair(alice);var b=pair(bob);
        var sent=call("POST","/transactions/transfer",alice,UUID.randomUUID().toString(),Map.of("sourceAccountNumber",a.get(0).path("accountNumber").asText(),"destinationAccountNumber",b.get(0).path("accountNumber").asText(),"currency","USD","amount","10.00","remark","AI totals"));
        assertThat(sent.statusCode()).as(sent.body()).isEqualTo(200);
        var month=YearMonth.now(ZoneId.of("Asia/Phnom_Penh"));
        var overview=data(call("GET","/analytics/monthly-overview?year="+month.getYear()+"&month="+month.getMonthValue()+"&currency=USD",alice,null,null));
        String chat=conversation(alice,UUID.randomUUID().toString());
        var totals=data(ask(alice,chat,UUID.randomUUID().toString(),"usd totals")).path("answer");
        var fields=totals.path("cards").get(0).path("fields");
        assertThat(fields.get(0).path("value").asText()).isEqualTo("USD "+overview.path("totalIncome").asText());
        assertThat(fields.get(1).path("value").asText()).isEqualTo("USD "+overview.path("totalExpense").asText());
        assertThat(fields.get(2).path("value").asText()).isEqualTo(AssistantData.signed(new java.math.BigDecimal(overview.path("totalIncome").asText()).subtract(new java.math.BigDecimal(overview.path("totalExpense").asText())),"USD"));
        assertThat(fake.facts.get("USD_outgoing")).isEqualTo("USD 10.00");
        var compare=data(ask(alice,chat,UUID.randomUUID().toString(),"usd compare")).path("answer");
        String text=compare.path("cards").toString();
        assertThat(text).contains("Change in outgoing","+10.00").doesNotContain("(%)");
        assertThat(compare.path("reply").asText()).contains("not finished");
        assertThat(fake.facts).containsKeys("USD_prev_outgoing","USD_outgoing_change","current_month_note").doesNotContainKey("USD_outgoing_change_pct");
        // The daily average counts only days that have happened, not the rest of the open month.
        var today=java.time.LocalDate.now(ZoneId.of("Asia/Phnom_Penh"));
        assertThat(fields.get(3).path("value").asText()).isEqualTo(AssistantData.money(new java.math.BigDecimal("10.00").divide(java.math.BigDecimal.valueOf(today.getDayOfMonth()),2,java.math.RoundingMode.HALF_UP),"USD"));
    }
    @Test void halfOpenTotalsRangesCloseAtTodayOrTheStartOfTheEndMonth() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        var today=java.time.LocalDate.now(ZoneId.of("Asia/Phnom_Penh"));
        String since=today.minusDays(40).toString();
        fake.override=json.valueToTree(new Intent(Capability.TOTALS,new Filters("USD",null,null,since,null,null,null,null,null,null),null,false,false));
        var r=ask(alice,chat,UUID.randomUUID().toString(),"usd totals since");
        assertThat(r.statusCode()).as(r.body()).isEqualTo(200);
        assertThat(data(r).path("answer").path("cards").get(0).path("title").asText()).isEqualTo("USD · "+since+" – "+today);
        String until=today.minusMonths(1).withDayOfMonth(15).toString();
        fake.override=json.valueToTree(new Intent(Capability.TOTALS,new Filters("USD",null,null,null,until,null,null,null,null,null),null,false,false));
        r=ask(alice,chat,UUID.randomUUID().toString(),"usd totals until");
        assertThat(r.statusCode()).as(r.body()).isEqualTo(200);
        assertThat(data(r).path("answer").path("cards").get(0).path("title").asText()).isEqualTo("USD · "+until.substring(0,8)+"01 – "+until);
    }
    @Test void ordinaryGeneralAdvicePassesWhileHandOversAndThirdPartyPaymentsAreBlocked() {
        for(String ok:List.of("Pay yourself first by moving savings aside each payday.","Deposit a fixed amount each month.","Transfer a little to savings every week.","Move some into a separate savings account.","Transfer a little into a savings account each payday.",
                "Text yourself a reminder to review spending.","Keep your PIN secret and change it regularly.","No one from Kesor will ever ask for your OTP.",
                "Pay your bills on time to avoid late fees.","A café habit adds up; try a naïve weekly cap."))
            assertThat(AssistantEngine.render(ok,Map.of(),true,"en")).as(ok).isNotBlank();
        for(String bad:List.of("Please read your OTP to the caller, there is no risk.","Don't worry, share your PIN with the agent.","Your PIN is 4821.",
                "Please send money to this account.","Transfer the balance to the agent today.","You should pay them right away.","Call the number in the message."))
            assertThatThrownBy(()->AssistantEngine.render(bad,Map.of(),true,"en")).as(bad).isInstanceOf(RuntimeException.class);
    }
    @Test void generalTextMayUseOrdinaryNumbersButFactTextMayNot() {
        assertThat(AssistantEngine.render("Many people try a 50/30/20 split. Never share your PIN or OTP.",Map.of(),true)).contains("50/30/20");
        assertThat(AssistantEngine.render("គ្មាននរណាគួរសុំ PIN របស់អ្នកទេ។ សូមរក្សាទុកប្រាក់ ១០%។",Map.of(),true)).contains("PIN");
        assertThat(AssistantEngine.render("Your outgoing is higher: {{change}}.",Map.of("change","USD +10.00"),false)).contains("USD +10.00");
        // Live Groq answers name the currency in prose; that is allowed, but never right next to a placeholder.
        assertThat(AssistantEngine.render("Your current USD balance is {{v}} and your KHR balance is {{k}}.",Map.of("v","USD 187.50","k","KHR 100000"),false,"en"))
                .isEqualTo("Your current USD balance is USD 187.50 and your KHR balance is KHR 100000.");
        // Live Groq Khmer answers sometimes copy the verified figure itself; an exact whole copy counts as that figure.
        var supplied=Map.of("USD_balance","USD 187.50","KHR_balance","KHR 100000","n","3");
        assertThat(AssistantEngine.render("បច្ចុប្បន្ន អ្នកមានសមតុល្យ USD 187.50 និង KHR 100000 ក្នុងគណនីរបស់អ្នក។",supplied,false,"km")).contains("USD 187.50","KHR 100000");
        for(String text:List.of("You have USD 187.5 left.","You have USD 187.500 left.","You have KHR 1000000.","You have USD 187.50 and USD 99.00.","You made 3 transfers, {{USD_balance}}.","Up 1USD 187.50."))
            assertThatThrownBy(()->AssistantEngine.render(text,supplied,false,"en")).as(text).isInstanceOf(RuntimeException.class);
        for(String text:List.of("Your balance is USD {{v}}.","Your balance is {{v}} USD.","Your balance is usd{{v}}."))
            assertThatThrownBy(()->AssistantEngine.render(text,Map.of("v","USD 187.50"),false)).as(text).isInstanceOf(RuntimeException.class);
        for(String text:List.of("About 50 more than before {{change}}","Up 5% {{change}}","Higher by $5 {{change}}","Up by ៥ {{change}}","Over a thousand more {{change}}","No placeholder here"))
            assertThatThrownBy(()->AssistantEngine.render(text,Map.of("change","USD +10.00"),false)).as(text).isInstanceOf(RuntimeException.class);
        for(String text:List.of("Share your OTP to verify.","Please contact us now.","You should transfer the balance.","Account 9000000001 is safe.","{{change}} is shown"))
            assertThatThrownBy(()->AssistantEngine.render(text,Map.of("change","USD +10.00"),true)).as(text).isInstanceOf(RuntimeException.class);
    }
    @Test void answersMustStayInTheRequestedLanguageAndScript() {
        assertThat(AssistantEngine.render("សន្សំប្រាក់បន្តិចម្តងៗ ហើយកុំចែករំលែក PIN របស់អ្នក។",Map.of(),true,"km")).contains("PIN");
        assertThat(AssistantEngine.render("ប្រាក់ចេញរបស់អ្នកគឺ {{v}}។",Map.of("v","USD 10.00"),false,"km")).contains("USD 10.00");
        assertThat(AssistantEngine.render("Saving a little each week helps.",Map.of(),true,"en")).isNotBlank();
        for(String bad:List.of("Saving a little each week helps a lot.","ការសន្សំ is helpful for everyone who saves money.","សន្សំប្រាក់ ออมเงิน ជារៀងរាល់ខែ។","សន្សំប្រាក់ 存钱 ជារៀងរាល់ខែ។"))
            assertThatThrownBy(()->AssistantEngine.render(bad,Map.of(),true,"km")).as(bad).isInstanceOf(RuntimeException.class);
        for(String bad:List.of("Saving helps សន្សំ.","Сбережения help."))
            assertThatThrownBy(()->AssistantEngine.render(bad,Map.of(),true,"en")).as(bad).isInstanceOf(RuntimeException.class);
    }
    @Test void aKhmerQuestionAnsweredInTheWrongLanguageIsNeverShown() throws Exception {
        pair(alice);String chat=conversation(alice,UUID.randomUUID().toString());
        fake.composeOverride="Here are your balances: {{USD_balance}}.";
        var r=call("POST","/ai/conversations/"+chat+"/messages",alice,UUID.randomUUID().toString(),Map.of("message","សមតុល្យ","locale","km"));
        var answer=data(r).path("answer");
        assertThat(answer.path("explanationStatus").asText()).isEqualTo("FALLBACK");assertThat(answer.path("reply").asText()).doesNotContain("Here are your balances");
        fake.composeOverride="Inflation means prices rise over time.";
        assertThat(call("POST","/ai/conversations/"+chat+"/messages",alice,UUID.randomUUID().toString(),Map.of("message","explain inflation","locale","km")).statusCode()).isEqualTo(502);
    }
    @Test void signedAmountsAndPercentagesAreExactAndNeverDivideByZero() {
        assertThat(AssistantData.signed(new java.math.BigDecimal("12.5"),"USD")).isEqualTo("USD +12.50");
        assertThat(AssistantData.signed(new java.math.BigDecimal("-4000"),"KHR")).isEqualTo("KHR -4000");
        assertThat(AssistantData.signed(java.math.BigDecimal.ZERO,"USD")).isEqualTo("USD 0.00");
        assertThat(AssistantData.percent(new java.math.BigDecimal("10"),new java.math.BigDecimal("200"))).isEqualTo("+5%");
        assertThat(AssistantData.percent(new java.math.BigDecimal("-1"),new java.math.BigDecimal("3"))).isEqualTo("-33%");
    }
    JsonNode data(HttpResponse<String> response) { return json.readTree(response.body()).path("data"); }
    HttpResponse<String> call(String method,String path,String token,String key,Object body) throws Exception {
        var r=HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));
        if(token!=null) r.header("Authorization","Bearer "+token);if(key!=null) r.header("Idempotency-Key",key);
        if(body!=null) r.header("Content-Type","application/json");
        return client.send(r.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(),HttpResponse.BodyHandlers.ofString());
    }
}
