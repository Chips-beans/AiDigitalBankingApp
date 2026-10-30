package com.bank.digital_banking;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UserWalletMerchantAccountTests extends PostgresIntegrationTest {

    @LocalServerPort
    int port;

    @Autowired
    ObjectMapper json;

    private final HttpClient http = HttpClient.newHttpClient();

    private HttpResponse<String> request(String method, String path, String token, Object body) throws Exception {
        var builder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1" + path))
                .header("Content-Type", "application/json");
        if (token != null) {
            builder.header("Authorization", "Bearer " + token);
        }
        if (body != null) {
            builder.method(method, HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body)));
        } else {
            builder.method(method, HttpRequest.BodyPublishers.noBody());
        }
        return http.send(builder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private JsonNode data(HttpResponse<String> response) throws Exception {
        JsonNode root = json.readTree(response.body());
        return root.has("data") ? root.path("data") : root;
    }

    private String signupUser(String prefix) throws Exception {
        String email = prefix + "_" + UUID.randomUUID().toString().substring(0, 8) + "@example.test";
        String username = prefix + "_" + UUID.randomUUID().toString().substring(0, 8);
        request("POST", "/auth/request-otp", null, Map.of("email", email, "purpose", "SIGNUP"));
        String code = SMTP.code(email);
        var res = request("POST", "/auth/register", null, Map.of(
                "username", username,
                "email", email,
                "password", PASSWORD,
                "otpCode", code,
                "deviceFingerprint", username,
                "deviceName", "TestDevice"
        ));
        assertThat(res.statusCode()).isEqualTo(201);
        return data(res).path("accessToken").asText();
    }

    @Test
    void userGetsTwoWalletsOnSignupAndCannotExceedLimit() throws Exception {
        String token = signupUser("wallet_limit");

        // 1. Verify 2 user wallets (USD and KHR) were created automatically
        var meRes = request("GET", "/accounts/me", token, null);
        assertThat(meRes.statusCode()).isEqualTo(200);
        JsonNode wallets = data(meRes);
        assertThat(wallets.size()).isEqualTo(2);

        String currency0 = wallets.get(0).path("currency").asText();
        String currency1 = wallets.get(1).path("currency").asText();
        assertThat(currency0).isIn("USD", "KHR");
        assertThat(currency1).isIn("USD", "KHR");
        assertThat(currency0).isNotEqualTo(currency1);

        assertThat(wallets.get(0).path("accountCategory").asText()).isEqualTo("WALLET");
        assertThat(wallets.get(1).path("accountCategory").asText()).isEqualTo("WALLET");
        assertThat(wallets.get(0).path("merchantId").isNull()).isTrue();

        // 2. Attempt to create a 3rd wallet account -> Rejected (limit 2)
        var thirdRes = request("POST", "/accounts", token, Map.of(
                "accountType", "SAVINGS",
                "currency", "USD",
                "initialDeposit", 0,
                "accountCategory", "WALLET"
        ));
        assertThat(thirdRes.statusCode()).isEqualTo(400);
        assertThat(thirdRes.body()).contains("ACCOUNT_LIMIT_EXCEEDED");

        // 3. Attempt to create duplicate currency wallet account -> Rejected
        var dupRes = request("POST", "/accounts", token, Map.of(
                "accountType", "SAVINGS",
                "currency", "KHR",
                "initialDeposit", 0
        ));
        assertThat(dupRes.statusCode()).isEqualTo(400);
        assertThat(dupRes.body()).contains("ACCOUNT_LIMIT_EXCEEDED");
    }

    @Test
    void nonMerchantCannotOpenMerchantAccounts() throws Exception {
        String token = signupUser("non_merchant");

        var res = request("POST", "/accounts", token, Map.of(
                "accountType", "CHECKING",
                "currency", "USD",
                "initialDeposit", 0,
                "accountCategory", "MERCHANT"
        ));
        assertThat(res.statusCode()).isEqualTo(403);
        assertThat(res.body()).contains("MERCHANT_REGISTRATION_REQUIRED");
    }

    @Test
    void merchantAppSignupCreatesTwoMerchantAccountsSeparatedFromUserWallets() throws Exception {
        String token = signupUser("merchant_user");

        // Fetch user ID
        var identityRes = request("GET", "/auth/me", token, null);
        long userId = data(identityRes).path("userId").asLong();

        // Initial wallets
        var walletsBefore = data(request("GET", "/accounts/me", token, null));
        assertThat(walletsBefore.size()).isEqualTo(2);

        // Sign up for merchant app
        String bakongId = "store_" + UUID.randomUUID().toString().substring(0, 8) + "@bank";
        var merchantRes = request("POST", "/merchants/register", token, Map.of(
                "storeName", "Lucky Coffee",
                "bakongAccountId", bakongId,
                "merchantCity", "Phnom Penh",
                "mcc", "5812",
                "ownerUserId", userId
        ));
        assertThat(merchantRes.statusCode()).isEqualTo(201);
        long merchantId = json.readTree(merchantRes.body()).path("id").asLong();

        // 1. GET /accounts/me (default) still returns ONLY the 2 user wallets
        var walletsAfter = data(request("GET", "/accounts/me", token, null));
        assertThat(walletsAfter.size()).isEqualTo(2);
        for (JsonNode w : walletsAfter) {
            assertThat(w.path("accountCategory").asText()).isEqualTo("WALLET");
            assertThat(w.path("merchantId").isNull()).isTrue();
        }

        // 2. GET /merchants/{id}/accounts returns the 2 separate merchant accounts
        var mchAccountsRes = request("GET", "/merchants/" + merchantId + "/accounts", token, null);
        assertThat(mchAccountsRes.statusCode()).isEqualTo(200);
        JsonNode mchAccounts = data(mchAccountsRes);
        assertThat(mchAccounts.size()).isEqualTo(2);

        String mchCur0 = mchAccounts.get(0).path("currency").asText();
        String mchCur1 = mchAccounts.get(1).path("currency").asText();
        assertThat(mchCur0).isIn("USD", "KHR");
        assertThat(mchCur1).isIn("USD", "KHR");
        assertThat(mchCur0).isNotEqualTo(mchCur1);
        assertThat(mchAccounts.get(0).path("accountCategory").asText()).isEqualTo("MERCHANT");
        assertThat(mchAccounts.get(1).path("accountCategory").asText()).isEqualTo("MERCHANT");
        assertThat(mchAccounts.get(0).path("merchantId").asLong()).isEqualTo(merchantId);
        assertThat(mchAccounts.get(1).path("merchantId").asLong()).isEqualTo(merchantId);

        // 3. GET /merchants/me/accounts returns the merchant accounts
        var myMchRes = request("GET", "/merchants/me/accounts", token, null);
        assertThat(myMchRes.statusCode()).isEqualTo(200);
        assertThat(data(myMchRes).size()).isEqualTo(2);

        // 4. GET /accounts/me?category=MERCHANT returns the 2 merchant accounts
        var mchCategoryRes = request("GET", "/accounts/me?category=MERCHANT", token, null);
        assertThat(mchCategoryRes.statusCode()).isEqualTo(200);
        assertThat(data(mchCategoryRes).size()).isEqualTo(2);

        // 5. GET /accounts/me?category=ALL returns all 4 accounts (2 wallets + 2 merchant)
        var allRes = request("GET", "/accounts/me?category=ALL", token, null);
        assertThat(allRes.statusCode()).isEqualTo(200);
        assertThat(data(allRes).size()).isEqualTo(4);

        // 6. Merchant cannot exceed 2 merchant accounts limit
        var thirdMchRes = request("POST", "/accounts", token, Map.of(
                "accountType", "CHECKING",
                "currency", "USD",
                "initialDeposit", 0,
                "accountCategory", "MERCHANT",
                "merchantId", merchantId
        ));
        assertThat(thirdMchRes.statusCode()).isEqualTo(400);
        assertThat(thirdMchRes.body()).contains("ACCOUNT_LIMIT_EXCEEDED");
    }

    @Test
    void continuationProfileCompletionAutomaticallyCreatesWallets() throws Exception {
        String email = "cont_" + UUID.randomUUID().toString().substring(0, 8) + "@example.test";
        request("POST", "/auth/email/request", null, Map.of("email", email));
        String code = SMTP.code(email);
        var verifyRes = request("POST", "/auth/email/verify", null, Map.of(
                "email", email,
                "otpCode", code,
                "deviceFingerprint", "cont-device",
                "deviceName", "ContinuationDevice"
        ));
        assertThat(verifyRes.statusCode()).isEqualTo(200);
        String token = data(verifyRes).path("accessToken").asText();

        // Complete profile
        var profileRes = request("PATCH", "/auth/profile", token, Map.of(
                "firstName", "Sophea",
                "lastName", "Chan"
        ));
        assertThat(profileRes.statusCode()).isEqualTo(200);

        // Verify wallets were automatically created
        var accountsRes = request("GET", "/accounts/me", token, null);
        assertThat(accountsRes.statusCode()).isEqualTo(200);
        JsonNode accounts = data(accountsRes);
        assertThat(accounts.size()).isEqualTo(2);
        assertThat(accounts.get(0).path("accountCategory").asText()).isEqualTo("WALLET");
        assertThat(accounts.get(1).path("accountCategory").asText()).isEqualTo("WALLET");
    }
}
