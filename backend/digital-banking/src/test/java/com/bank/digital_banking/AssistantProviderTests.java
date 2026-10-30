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
    HttpServer server; ExecutorService serverPool; GeminiAdapter adapter; AIProperties settings;
    volatile int status=200; volatile String output="{\"text\":\"Verified: {{value}}\"}", finish="STOP";
    volatile String path,key,body;AtomicInteger hits=new AtomicInteger();
    volatile CountDownLatch entered,release;
    @BeforeEach void start() throws Exception {
        server=HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(),0),0);
        serverPool=Executors.newCachedThreadPool();server.setExecutor(serverPool);
        server.createContext("/",exchange -> {
            hits.incrementAndGet();path=exchange.getRequestURI().toString();key=exchange.getRequestHeaders().getFirst("x-goog-api-key");body=new String(exchange.getRequestBody().readAllBytes(),StandardCharsets.UTF_8);
            if(entered!=null) {entered.countDown();try {release.await(5,TimeUnit.SECONDS);}catch(InterruptedException ex){Thread.currentThread().interrupt();}}
            if(status==302) exchange.getResponseHeaders().set("Location","http://127.0.0.1:1/private");
            byte[] response=json.writeValueAsBytes(Map.of("candidates",List.of(Map.of("finishReason",finish,"content",Map.of("parts",List.of(Map.of("text",output)))))));
            exchange.getResponseHeaders().set("Content-Type","application/json");exchange.sendResponseHeaders(status,response.length);
            try(var stream=exchange.getResponseBody()) {stream.write(response);}finally{exchange.close();}
        });server.start();
        settings=new AIProperties();settings.setEnabled(true);settings.setCustomerContextEnabled(true);settings.setApiKey("fixture-provider-key-only");
        settings.setApiUrl("http://localhost:"+server.getAddress().getPort());adapter=new GeminiAdapter(settings,json);
    }
    @AfterEach void stop() {if(release!=null) release.countDown();server.stop(0);serverPool.shutdownNow();}
    long deadline() {return System.nanoTime()+Duration.ofSeconds(2).toNanos();}
    @Test void usesHeaderStatelessSchemaAndBoundedGenerationWithoutKeyInUrl() {
        assertThat(adapter.explain(Map.of("value","USD 200.00"),"en",deadline())).isEqualTo("Verified: {{value}}");
        assertThat(key).isEqualTo(settings.getApiKey());assertThat(path).doesNotContain(settings.getApiKey(),"?key").contains("/models/gemini-3.8-flash:generateContent");
        var request=json.readTree(body);
        assertThat(request.path("generationConfig").path("maxOutputTokens").asInt()).isEqualTo(2048);
        assertThat(request.path("generationConfig").path("responseJsonSchema").path("additionalProperties").asBoolean()).isFalse();
        assertThat(request.path("contents").size()).isEqualTo(1);
    }
    @Test void disabledOrUnreviewedConfigurationNeverMakesProviderCall() {
        var defaults=new AIProperties();assertThat(defaults.isEnabled()).isFalse();assertThat(defaults.getModel()).isEqualTo("gemini-3.8-flash");
        settings.setCustomerContextEnabled(false);assertThat(adapter.available()).isFalse();
        assertThatThrownBy(()->adapter.explain(Map.of("value","USD 1.00"),"en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_UNAVAILABLE"));
        assertThat(hits.get()).isZero();
    }
    @Test void providerFailuresMalformedBlockedAndRedirectResponsesAreTyped() {
        status=429;
        assertThatThrownBy(()->adapter.explain(Map.of(),"en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_PROVIDER_RATE_LIMITED"));
        status=302;
        assertThatThrownBy(()->adapter.explain(Map.of(),"en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_UNAVAILABLE"));
        status=200;finish="SAFETY";
        assertThatThrownBy(()->adapter.explain(Map.of(),"en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
        finish="STOP";output="not JSON";
        assertThatThrownBy(()->adapter.explain(Map.of(),"en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_INVALID_RESPONSE"));
    }
    @Test void deadlineStopsCallsAndGlobalConcurrencyIsLimitedToTwo() throws Exception {
        assertThatThrownBy(()->adapter.classify("synthetic",System.nanoTime()-1)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_TIMEOUT"));
        assertThat(hits.get()).isZero();
        entered=new CountDownLatch(2);release=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var a=pool.submit(()->adapter.explain(Map.of("value","1"),"en",deadline()));
            var b=pool.submit(()->adapter.explain(Map.of("value","1"),"en",deadline()));
            assertThat(entered.await(2,TimeUnit.SECONDS)).isTrue();
            assertThatThrownBy(()->adapter.explain(Map.of(),"en",deadline())).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.getCode()).isEqualTo("AI_BUSY"));
            release.countDown();a.get();b.get();assertThat(hits.get()).isEqualTo(2);
        } finally {release.countDown();}
    }
}
