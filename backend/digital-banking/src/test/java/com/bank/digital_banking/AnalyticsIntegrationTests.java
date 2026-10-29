package com.bank.digital_banking;

import com.bank.digital_banking.module.analytics.service.AnalyticsService;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.common.exception.ApiException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.*;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class AnalyticsIntegrationTests extends PostgresIntegrationTest {
    @Autowired AnalyticsService analytics;
    @Autowired UserRepository users;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper json;
    @Value("${local.server.port}") int port;
    User alice, bob;
    long a, other, b, khr;
    String number;

    @BeforeEach void fixtures() {
        jdbc.update("DELETE FROM transactions WHERE reference_number LIKE 'ANL-%'");
        alice = users.findByUsername("alice.demo").orElseThrow();
        bob = users.findByUsername("bob.demo").orElseThrow();
        number = "78" + Long.toString(System.nanoTime()).substring(0, 12);
        a = account(alice, number, "USD", "FROZEN");
        other = account(alice, number + "1", "USD", "CLOSED");
        b = account(bob, number + "2", "USD", "ACTIVE");
        khr = account(alice, number + "3", "KHR", "ACTIVE");
    }

    long account(User owner, String num, String currency, String status) {
        return jdbc.queryForObject("INSERT INTO accounts(user_id,account_number,account_type,currency,balance,status) "
                + "VALUES (?,?,'SAVINGS',?,0,?) RETURNING id", Long.class, owner.getId(), num, currency, status);
    }

    void posting(Long src, Long dst, String amount, String currency, String type, String status, String instant) {
        jdbc.update("INSERT INTO transactions(reference_number,source_account_id,destination_account_id,amount,currency,transaction_type,status,created_at) "
                + "VALUES (?,?,?,?,?,?,?,?)", "ANL-" + UUID.randomUUID().toString().replace("-", ""),
                src, dst, new BigDecimal(amount), currency, type, status, Timestamp.from(Instant.parse(instant)));
    }

    @Test void directionOwnAccountsStatusCurrenciesAndZeroFill() {
        posting(null, a, "100.25", "USD", "DEPOSIT", "SUCCESS", "2088-02-04T00:00:00Z");
        posting(b, other, "30.10", "USD", "TRANSFER", "SUCCESS", "2088-02-04T01:00:00Z");
        posting(a, b, "20.15", "USD", "TRANSFER", "SUCCESS", "2088-02-05T00:00:00Z");
        posting(other, null, "5.00", "USD", "WITHDRAWAL", "SUCCESS", "2088-02-05T00:00:00Z");
        posting(a, other, "900.00", "USD", "TRANSFER", "SUCCESS", "2088-02-05T00:00:00Z");
        for (String status : List.of("FAILED", "PENDING", "REVERSED"))
            posting(b, a, "999.00", "USD", "TRANSFER", status, "2088-02-06T00:00:00Z");
        posting(null, khr, "4000", "KHR", "DEPOSIT", "SUCCESS", "2088-02-04T00:00:00Z");
        var usd = analytics.getMonthlyOverview(alice, 2088, 2, "USD");
        assertThat(usd.totalIncome()).isEqualTo("130.35");
        assertThat(usd.totalExpense()).isEqualTo("25.15");
        assertThat(usd.daily()).hasSize(29);
        assertThat(usd.daily().get(0).totalIncome()).isEqualTo("0.00");
        assertThat(usd.daily().get(3).totalIncome()).isEqualTo("130.35");
        assertThat(usd.daily().stream().map(d -> new BigDecimal(d.totalIncome())).reduce(BigDecimal.ZERO, BigDecimal::add))
                .isEqualByComparingTo(usd.totalIncome());
        assertThat(usd.daily().stream().map(d -> new BigDecimal(d.totalExpense())).reduce(BigDecimal.ZERO, BigDecimal::add))
                .isEqualByComparingTo(usd.totalExpense());
        assertThat(analytics.getMonthlyOverview(alice, 2088, 2, "KHR").totalIncome()).isEqualTo("4000");
        var bobData = analytics.getMonthlyOverview(bob, 2088, 2, "USD");
        assertThat(bobData.totalIncome()).isEqualTo("20.15");
        assertThat(bobData.totalExpense()).isEqualTo("30.10");
    }

    @Test void phnomPenhMidnightMonthEdgesAndLegacyShapesAgree() {
        posting(b, a, "1.01", "USD", "TRANSFER", "SUCCESS", "2088-01-31T16:59:59Z");
        posting(b, a, "2.02", "USD", "TRANSFER", "SUCCESS", "2088-01-31T17:00:00Z");
        posting(a, b, "3.03", "USD", "TRANSFER", "SUCCESS", "2088-02-01T16:59:59Z");
        posting(b, a, "4.04", "USD", "TRANSFER", "SUCCESS", "2088-02-01T17:00:00Z");
        posting(b, a, "5.05", "USD", "TRANSFER", "SUCCESS", "2088-02-29T16:59:59Z");
        posting(b, a, "6.06", "USD", "TRANSFER", "SUCCESS", "2088-02-29T17:00:00Z");
        var daily = analytics.getDailyTransactionsForMonth(alice, number, 2088, 2);
        assertThat(daily.get(0).totalIncome()).isEqualByComparingTo("2.02");
        assertThat(daily.get(0).totalExpense()).isEqualByComparingTo("3.03");
        assertThat(daily.get(1).totalIncome()).isEqualByComparingTo("4.04");
        assertThat(daily.get(28).totalIncome()).isEqualByComparingTo("5.05");
        var summary = analytics.getMonthlySummary(alice, number, 2088, 2);
        assertThat(summary.totalIncome()).isEqualByComparingTo("11.11");
        assertThat(summary.netSavings()).isEqualByComparingTo("8.08");
        var semester = analytics.getSemesterComparison(alice, number, 2088, 2);
        assertThat(semester.monthlyData()).hasSize(6);
        assertThat(semester.semesterTotalIncome()).isEqualByComparingTo("12.12");
        assertThatThrownBy(() -> analytics.getMonthlySummary(bob, number, 2088, 2))
                .isInstanceOf(ApiException.class).hasMessageContaining("permission");
    }

    @Test void emptyCalendarAndTotalsLargerThanTransactionLimit() {
        assertThat(analytics.getMonthlyOverview(alice, 2087, 2, "USD").daily()).hasSize(28);
        assertThat(analytics.getMonthlyOverview(alice, 2088, 4, "USD").daily()).hasSize(30);
        assertThat(analytics.getMonthlyOverview(alice, 2088, 1, "USD").daily()).hasSize(31);
        for (int i = 0; i < 2; i++)
            posting(null, a, "9999999999999.99", "USD", "DEPOSIT", "SUCCESS", "2088-02-01T00:00:00Z");
        assertThat(analytics.getMonthlyOverview(alice, 2088, 2, "USD").totalIncome()).isEqualTo("19999999999999.98");
        assertThat(analytics.getMonthlyOverview(alice, 2088, 3, "USD").totalIncome()).isEqualTo("0.00");
    }

    @Test void httpAuthenticationValidationAndWireContract() throws Exception {
        String query = "/analytics/monthly-overview?year=2088&month=2&currency=USD";
        assertThat(call("GET", query, null, null).statusCode()).isEqualTo(401);
        jdbc.update("DELETE FROM otp_rate_limits");
        call("POST", "/auth/request-otp", null, Map.of("email", alice.getEmail(), "purpose", "LOGIN"));
        var login = call("POST", "/auth/login", null, Map.of("usernameOrEmail", alice.getEmail(), "password", PASSWORD,
                "otpCode", SMTP.code(alice.getEmail()), "deviceFingerprint", "analytics-" + UUID.randomUUID(),
                "deviceName", "Isolated test", "deviceType", "ANDROID"));
        assertThat(login.statusCode()).as(login.body()).isEqualTo(200);
        String token = json.readTree(login.body()).path("data").path("accessToken").asText();
        var response = call("GET", query, token, null);
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        var data = json.readTree(response.body()).path("data");
        assertThat(data.path("timeZone").asText()).isEqualTo("Asia/Phnom_Penh");
        assertThat(data.path("month").asText()).isEqualTo("2088-02");
        assertThat(data.path("totalIncome").isString()).isTrue();
        assertThat(data.path("daily").size()).isEqualTo(29);
        for (String bad : List.of("year=0&month=1&currency=USD", "year=2088&month=13&currency=USD",
                "year=2088&month=2&currency=EUR", "year=no&month=2&currency=USD")) {
            var invalid = call("GET", "/analytics/monthly-overview?" + bad, token, null);
            assertThat(invalid.statusCode()).as(invalid.body()).isEqualTo(400);
            assertThat(json.readTree(invalid.body()).path("error").asText()).isEqualTo("INVALID_REQUEST");
        }
        var legacy = call("GET", "/analytics/daily?accountNumber=" + number + "&year=2088&month=2", token, null);
        assertThat(json.readTree(legacy.body()).isArray()).isTrue();
    }

    HttpResponse<String> call(String method, String path, String token, Object body) throws Exception {
        var builder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1" + path));
        if (token != null) builder.header("Authorization", "Bearer " + token);
        if (body != null) builder.header("Content-Type", "application/json");
        return HttpClient.newHttpClient().send(builder.method(method, body == null
                ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(),
                HttpResponse.BodyHandlers.ofString());
    }
}
