package com.bank.digital_banking;

import com.bank.digital_banking.module.ai.adapter.*;
import com.bank.digital_banking.common.exception.ApiException;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.*;
import tools.jackson.databind.json.JsonMapper;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.assertj.core.api.Assertions.*;

class AssistantProviderTests {
    final JsonMapper json=JsonMapper.builder().build();
    HttpServer server; ExecutorService serverPool; GatewayAdapter adapter; AIProperties settings;
    volatile int status=200; volatile String output="{\"text\":\"Verified: {{value}}\"}", finish="stop";
    volatile String path,key,body;AtomicInteger hits=new AtomicInteger(),rejectionsLeft=new AtomicInteger();
    // Groq's strict-mode refusal; failed_generation echoes model output and must never be logged or used.
    volatile String rejection="{\"error\":{\"message\":\"Failed to validate JSON\",\"type\":\"invalid_request_error\",\"code\":\"json_validate_failed\",\"failed_generation\":\"secret model text\"}}";
    volatile CountDownLatch entered,release;
    @BeforeEach void start() throws Exception {
        server=HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(),0),0);
        serverPool=Executors.newCachedThreadPool();server.setExecutor(serverPool);
        server.createContext("/",exchange -> {
            hits.incrementAndGet();path=exchange.getRequestURI().toString();key=exchange.getRequestHeaders().getFirst("Authorization");body=new String(exchange.getRequestBody().readAllBytes(),StandardCharsets.UTF_8);
            if(entered!=null) {entered.countDown();try {release.await(5,TimeUnit.SECONDS);}catch(InterruptedException ex){Thread.currentThread().interrupt();}}
            if(status==302) exchange.getResponseHeaders().set("Location","http://127.0.0.1:1/private");
            if(rejectionsLeft.getAndDecrement()>0) {
                byte[] error=rejection.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().set("Content-Type","application/json");exchange.sendResponseHeaders(400,error.length);
                try(var stream=exchange.getResponseBody()) {stream.write(error);}finally{exchange.close();}
                return;
            }
            byte[] response=json.writeValueAsBytes(Map.of("choices",List.of(Map.of("finish_reason",finish,"message",Map.of("role","assistant","content",output)))));
            exchange.getResponseHeaders().set("Content-Type","application/json");exchange.sendResponseHeaders(status,response.length);
            try(var stream=exchange.getResponseBody()) {stream.write(response);}finally{exchange.close();}
        });server.start();
        settings=new AIProperties();settings.setEnabled(true);settings.setCustomerContextEnabled(true);settings.setApiKey("fixture-provider-key-only");
        settings.setApiUrl("http://localhost:"+server.getAddress().getPort());adapter=new GatewayAdapter(settings,json);
    }
    @AfterEach void stop() {if(release!=null) release.countDown();server.stop(0);serverPool.shutdownNow();}
    long deadline() {return System.nanoTime()+Duration.ofSeconds(2).toNanos();}
    @Test void usesBearerHeaderStatelessChatRequestAndBoundedGenerationWithoutKeyInUrl() {
        assertThat(adapter.compose("How much do I have?",Map.of("value","USD 200.00"),"ACCOUNT","en",deadline())).isEqualTo("Verified: {{value}}");
        assertThat(key).isEqualTo("Bearer "+settings.getApiKey());assertThat(path).isEqualTo("/chat/completions").doesNotContain(settings.getApiKey(),"key=");
        var request=json.readTree(body);
        assertThat(request.path("model").asText()).isEqualTo("qwen/qwen3.8-27b");assertThat(request.path("reasoning_effort").asText()).isEqualTo("none");
        assertThat(request.path("max_tokens").asInt()).as("answer allowance stays under Groq's free-tier 1000/min output budget").isEqualTo(700);assertThat(request.path("stream").asBoolean(true)).isFalse();
        assertThat(request.path("messages").size()).isEqualTo(2);
        assertThat(request.path("messages").get(0).path("role").asText()).isEqualTo("system");assertThat(request.path("messages").get(1).path("role").asText()).isEqualTo("user");
        var format=request.path("response_format");
        assertThat(format.path("type").asText()).isEqualTo("json_schema");
        assertThat(format.path("json_schema").path("strict").asBoolean()).isTrue();assertThat(format.path("json_schema").path("name").asText()).isEqualTo("kesor_answer");
        assertThat(format.path("json_schema").path("schema").path("required").toString()).isEqualTo("[\"text\"]");
        assertThat(request.path("messages").get(0).path("content").asText()).contains("one JSON object only");
    }
    String userContent() { return json.readTree(body).path("messages").get(1).path("content").asText(); }
    @Test void generalModeSendsNoFactsAndAccountModeSendsOnlySuppliedFacts() {
        adapter.compose("What is an emergency fund?",Map.of("secret_balance","USD 5.00"),"GENERAL","en",deadline());
        var general=json.readTree(userContent());
        assertThat(general.path("mode").asText()).isEqualTo("GENERAL");assertThat(general.has("facts")).isFalse();
        assertThat(body).doesNotContain("secret_balance");
        adapter.compose("Compare",Map.of("USD_outgoing","USD 1.00"),"MIXED","km",deadline());
        var mixed=json.readTree(userContent());
        assertThat(mixed.path("facts").path("USD_outgoing").asText()).isEqualTo("USD 1.00");
        assertThat(body).contains("Khmer").contains("licensed professional");
    }
    @Test void jsonInsideAFenceOrPreambleIsAcceptedButOnlyOneObject() {
        output="Here you go:\n```json\n{\"text\":\"Fenced {{value}}\"}\n```";
        assertThat(adapter.compose("q",Map.of("value","USD 1.00"),"ACCOUNT","en",deadline())).isEqualTo("Fenced {{value}}");
        output="{\"capability\":\"HELP\",\"filters\":{},\"topic\":null,\"followUp\":false,\"general\":false}";
        assertThat(adapter.classify("Current customer question: help",deadline()).path("capability").asText()).isEqualTo("HELP");
        var intent=json.readTree(body);
        assertThat(intent.path("response_format").path("json_schema").path("name").asText()).isEqualTo("kesor_intent");
        assertThat(intent.path("response_format").path("json_schema").path("schema").path("required").toString()).contains("general");
        assertThat(intent.path("messages").get(0).path("content").asText()).as("strict mode carries the schema, so the prompt stays short").doesNotContain("JSON Schema");
        // Every intent key is spelled out for the model (Groq checks strict output only after generation).
        assertThat(intent.path("messages").get(0).path("content").asText()).contains(GatewayAdapter.INTENT_EXAMPLE);
        var example=json.readTree(GatewayAdapter.INTENT_EXAMPLE);var schema=json.valueToTree(GatewayAdapter.intentSchema());
        assertThat(example.propertyNames()).containsExactlyInAnyOrderElementsOf(schema.path("properties").propertyNames());
        assertThat(example.path("filters").propertyNames()).containsExactlyInAnyOrderElementsOf(schema.path("properties").path("filters").path("properties").propertyNames());
        settings.setJsonMode("prompt");
        adapter.classify("Current customer question: help",deadline());
        assertThat(json.readTree(body).has("response_format")).isFalse();
        assertThat(json.readTree(body).path("messages").get(0).path("content").asText()).contains("JSON Schema","\"general\"");
        settings.setJsonMode("object");settings.setReasoningEffort(" ");
        adapter.classify("Current customer question: help",deadline());
        assertThat(json.readTree(body).path("response_format").path("type").asText()).isEqualTo("json_object");
        assertThat(json.readTree(body).has("reasoning_effort")).isFalse();
        settings.setJsonMode("schema");settings.setReasoningEffort("none");
        output="{\"text\":1}";
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
        output="[1,2]";
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
    }
    @Test void inlineThinkingIsRemovedAndThinkingAloneIsInvalid() {
        output="<think>The customer wants a balance.</think>{\"text\":\"Clean {{value}}\"}";
        assertThat(adapter.compose("q",Map.of("value","USD 1.00"),"ACCOUNT","en",deadline())).isEqualTo("Clean {{value}}");
        output="<think>only thinking</think>";
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
    }
    @Test void theKeyIsOnlySentOverHttpsOrToLoopback() {
        for(String url:List.of("http://gateway.example.com/v1","ftp://x/v1","not a url","")) {
            settings.setApiUrl(url);assertThat(adapter.available()).as(url).isFalse();
        }
        settings.setApiUrl("https://gateway.example.com/v1");assertThat(adapter.available()).isTrue();
        assertThat(hits.get()).isZero();
    }
    @Test void aRejectedJsonGenerationIsRetriedOnceThenTreatedAsInvalid() {
        rejectionsLeft.set(1);
        assertThat(adapter.compose("q",Map.of("value","USD 1.00"),"ACCOUNT","en",deadline())).isEqualTo("Verified: {{value}}");
        assertThat(hits.get()).isEqualTo(2);
        // Twice in a row: invalid response (so data answers fall back to verified cards), never a third call.
        hits.set(0);rejectionsLeft.set(2);
        assertThatThrownBy(()->adapter.compose("q",Map.of("value","USD 1.00"),"ACCOUNT","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
        assertThat(hits.get()).isEqualTo(2);
        // Any other 400 is not retried and stays "unavailable".
        hits.set(0);rejectionsLeft.set(1);rejection="{\"error\":{\"code\":\"model_not_found\"}}";
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_UNAVAILABLE"));
        assertThat(hits.get()).isEqualTo(1);
        // Plain-text completions never request a JSON format, so they are not retried either.
        hits.set(0);rejectionsLeft.set(1);rejection="{\"error\":{\"code\":\"json_validate_failed\"}}";
        assertThatThrownBy(()->adapter.generateCompletion("s","i")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_UNAVAILABLE"));
        assertThat(hits.get()).isEqualTo(1);
        assertThat(adapter.errorCode("{\"error\":{\"code\":\"bad code with spaces\"}}".getBytes())).isEqualTo("unknown");
        assertThat(adapter.errorCode("not json".getBytes())).isEqualTo("unknown");
    }
    @Test void legacyGeminiSettingsAreReportedByNameOnly() {
        var env=new org.springframework.mock.env.MockEnvironment().withProperty("GEMINI_API_KEY","old-key").withProperty("AI_API_KEY","new");
        assertThat(AIConfigCheck.legacySettings(env)).containsExactly("GEMINI_API_KEY");
        assertThat(AIConfigCheck.legacySettings(new org.springframework.mock.env.MockEnvironment())).isEmpty();
    }
    @Test void disabledOrUnreviewedConfigurationNeverMakesProviderCall() {
        var defaults=new AIProperties();assertThat(defaults.isEnabled()).isFalse();assertThat(defaults.getModel()).isEqualTo("qwen/qwen3.8-27b");assertThat(defaults.getApiUrl()).isEqualTo("https://api.groq.com/openai/v1");
        assertThat(defaults.getJsonMode()).isEqualTo("schema");assertThat(defaults.getReasoningEffort()).isEqualTo("none");
        settings.setCustomerContextEnabled(false);assertThat(adapter.available()).isFalse();
        assertThatThrownBy(()->adapter.compose("q",Map.of("value","USD 1.00"),"ACCOUNT","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_UNAVAILABLE"));
        assertThat(hits.get()).isZero();
    }
    @Test void providerFailuresMalformedBlockedAndRedirectResponsesAreTyped() {
        status=429;
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_PROVIDER_RATE_LIMITED"));
        status=302;
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_UNAVAILABLE"));
        status=200;finish="length";
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
        finish="stop";output="not JSON";
        assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
    }
    @Test void deadlineStopsCallsAndGlobalConcurrencyIsLimitedToTwo() throws Exception {
        assertThatThrownBy(()->adapter.classify("synthetic",System.nanoTime()-1)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_TIMEOUT"));
        assertThat(hits.get()).isZero();
        entered=new CountDownLatch(2);release=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var a=pool.submit(()->adapter.compose("q",Map.of("value","1"),"ACCOUNT","en",deadline()));
            var b=pool.submit(()->adapter.compose("q",Map.of("value","1"),"ACCOUNT","en",deadline()));
            assertThat(entered.await(2,TimeUnit.SECONDS)).isTrue();
            assertThatThrownBy(()->adapter.compose("q",Map.of(),"GENERAL","en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_BUSY"));
            release.countDown();a.get();b.get();assertThat(hits.get()).isEqualTo(2);
        } finally {release.countDown();}
    }
}
