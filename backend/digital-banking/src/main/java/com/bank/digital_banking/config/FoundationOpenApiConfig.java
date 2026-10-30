package com.bank.digital_banking.config;

import com.bank.digital_banking.common.dto.ApiErrorResponse;
import io.swagger.v3.core.converter.ModelConverters;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.SpecVersion;
import io.swagger.v3.oas.models.headers.Header;
import io.swagger.v3.oas.models.media.*;
import io.swagger.v3.oas.models.responses.ApiResponse;
import io.swagger.v3.oas.models.responses.ApiResponses;
import org.springdoc.core.customizers.GlobalOpenApiCustomizer;
import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

/** Documentation of the delivered foundation; does not change runtime authorization. */
@Configuration
public class FoundationOpenApiConfig {
    // ===================================================================
    // Swagger UI Group: Foundation Milestone (Authentication, Accounts, Transactions)
    // ===================================================================
    @Bean
    GroupedOpenApi foundationApi() {
        return GroupedOpenApi.builder().group("foundation")
                .displayName("Foundation (Core Banking)")
                .pathsToMatch("/api/v1/auth/**", "/api/v1/accounts", "/api/v1/accounts/**",
                        "/api/v1/transactions/**").build();
    }

    @Bean
    GlobalOpenApiCustomizer foundationContracts() {
        return api -> {
            ModelConverters.getInstance(api.getSpecVersion() == SpecVersion.V31).read(ApiErrorResponse.class)
                    .forEach((name, schema) -> api.getComponents().addSchemas(name, schema));
            // Optional Java reference values accept/emit JSON null, not just an absent key.
            describe(api, "/accounts/pairs", PathItem.HttpMethod.POST, "Accounts", "Open USD and KHR accounts together",
                    "Customer only. Required Idempotency-Key. Atomic creation and server-controlled non-production opening credits; replay returns the original pair.",
                    "201", false, Map.of("accountType", "SAVINGS"), "400", "401", "403", "409", "503");
            describe(api, "/accounts/opening-policy", PathItem.HttpMethod.GET, "Accounts", "Read opening balances",
                    "Server-authoritative USD/KHR opening amounts and explicit test-funding status. Production never permits test opening credits.",
                    "200", false, null, "401", "403");
            nullable(api, "ApiErrorResponse", "retryAfterSeconds");
            nullable(api, "RegisterRequestDto", "firstName", "lastName", "deviceType");
            nullable(api, "LoginRequestDto", "deviceType");
            nullable(api, "SessionIdentityDto", "email", "firstName", "lastName");
            nullable(api, "TelegramExchangeResponse", "tokens");
            describe(api, "/auth/pin/prepare", PathItem.HttpMethod.POST, "Authentication", "Prepare app PIN gate",
                    "Authenticated, completed customer profile. Locks this session and returns an opaque device/session-bound app ticket. Persist this instead of banking refresh tokens.",
                    "200", false, null, "401", "403");
            for (String path : List.of("status", "setup", "unlock", "discard")) {
                describe(api, "/auth/pin/" + path, PathItem.HttpMethod.POST, "Authentication", "App PIN: " + path,
                        "Authorized by the private app ticket in the JSON body. Five wrong PINs require fresh verified identity recovery. Setup/reset requires matching four-digit values; reset requires a fresh identity session and revokes other sessions. Never log tickets or PINs.",
                        "200", true, null, "400", "401", "403");
            }
            describe(api, "/auth/email/request", PathItem.HttpMethod.POST, "Authentication", "Continue with email: request a code",
                    "Public. The same flow serves new and returning customers. No profile is created until ownership is verified.",
                    "200", true, Map.of("email", "customer@example.test"), "400", "429", "503");
            describe(api, "/auth/email/verify", PathItem.HttpMethod.POST, "Authentication", "Verify email and continue",
                    "Public. Consumes a CONTINUE code once. Read /auth/me: profileComplete=false requires onboarding before banking access.",
                    "200", true, Map.of("email", "customer@example.test", "otpCode", "123456", "deviceFingerprint", "browser-installation",
                            "deviceName", "Browser", "deviceType", "WEB"), "400", "401", "409");
            describe(api, "/auth/profile", PathItem.HttpMethod.PATCH, "Authentication", "Complete your information",
                    "Authenticated onboarding profiles only gain banking permissions after this succeeds. Existing complete profiles remain unchanged.",
                    "200", false, Map.of("firstName", "Dara", "lastName", "Sok"), "400", "401");
            describe(api, "/auth/email/link/request", PathItem.HttpMethod.POST, "Authentication", "Request a code to connect email",
                    "Authenticated. Codes are bound to this profile. Verify the code before connecting the email identity.",
                    "200", false, Map.of("email", "customer@example.test"), "400", "401", "429");
            describe(api, "/auth/email/link/verify", PathItem.HttpMethod.POST, "Authentication", "Connect verified email",
                    "Authenticated. A new onboarding-only Telegram profile can connect to an existing verified email profile. Complete profiles are never automatically merged.",
                    "200", false, Map.of("email", "customer@example.test", "otpCode", "123456", "deviceFingerprint", "browser-installation",
                            "deviceName", "Browser", "deviceType", "WEB"), "400", "401", "409");
            for (String start : List.of("/auth/telegram/start", "/auth/telegram/link/start"))
                describe(api, start, PathItem.HttpMethod.POST, "Authentication", "Start Telegram approval",
                        "Open authorizationUrl in a browser. Keep flowId and exchangeSecret private in the initiating browser. Linking requires authentication within ten minutes.",
                        "200", start.endsWith("/telegram/start"), Map.of("deviceFingerprint", "browser-installation", "deviceName", "Browser", "deviceType", "WEB"),
                        "400", "401", "403", "429", "503");
            describe(api, "/auth/telegram/exchange", PathItem.HttpMethod.POST, "Authentication", "Collect Telegram approval",
                    "Public, authorized by the flow's private exchangeSecret. PENDING can be polled; COMPLETE issues tokens exactly once. No additional app OTP.",
                    "200", true, Map.of("flowId", "PASTE_FLOW_ID", "exchangeSecret", "PASTE_PRIVATE_EXCHANGE_SECRET"), "400", "401", "409");
            for (String path : List.of("/auth/telegram/native/start", "/auth/telegram/native/link/start"))
                describe(api, path, PathItem.HttpMethod.POST, "Authentication", "Start native Android Telegram approval",
                        "Returns a state/nonce/PKCE-bound authorization URL and the registered Android App Link. Keep exchangeSecret private. Linking requires recent authentication.",
                        "200", path.endsWith("/native/start"), Map.of("deviceFingerprint", "android-installation", "deviceName", "Android", "deviceType", "ANDROID"),
                        "400", "401", "403", "429", "503");
            describe(api, "/auth/telegram/native/exchange", PathItem.HttpMethod.POST, "Authentication", "Complete native Telegram approval once",
                    "Requires the initiating app's private exchangeSecret and the code delivered to its verified App Link. Consumed before contacting Telegram; never retry an uncertain exchange. Start a new approval instead.",
                    "200", true, Map.of("flowId", "PASTE_FLOW_ID", "exchangeSecret", "PASTE_PRIVATE_EXCHANGE_SECRET", "code", "PROVIDER_CODE"),
                    "400", "401", "403", "409", "503");
            if (api.getPaths() != null && api.getPaths().get("/api/v1/auth/telegram/callback") != null) {
                var callback = api.getPaths().get("/api/v1/auth/telegram/callback").getGet();
                callback.setSecurity(List.of());
                callback.setTags(List.of("Authentication"));
                callback.setSummary("Telegram browser callback (not called manually)");
            }
            nullable(api, "TransferRequestDto", "remark");
            nullable(api, "DepositRequestDto", "remark");
            nullable(api, "TransactionResponseDto", "sourceAccountNumber", "destinationAccountNumber", "remark");
            describe(api, "/auth/request-otp", PathItem.HttpMethod.POST, "Authentication", "Request an email OTP",
                    "Public. Use SIGNUP for a new email or LOGIN for an enabled existing user. "
                            + "Read the code in the configured inbox; it is never returned here. "
                            + "Ineligible emails receive the same acceptance response without an email. "
                            + "Defaults: 5-minute expiry, 60-second resend cooldown, 5 requests per 15 minutes.",
                    "200", true, Map.of("email", "alice.demo@example.test", "purpose", "LOGIN"), "400", "429", "503");
            describe(api, "/auth/register", PathItem.HttpMethod.POST, "Authentication", "Register a customer and sign in",
                    "Public. Requires an unused SIGNUP OTP. Creates ROLE_CUSTOMER and a session, not a bank account. "
                            + "Save data.accessToken and data.refreshToken. Replace example email/username for repeated tests.",
                    "201", true, Map.of("username", "foundation.customer", "email", "foundation.customer@example.test",
                            "password", "ChooseYourTestPassword!", "otpCode", "123456",
                            "deviceFingerprint", "swagger-foundation-001", "deviceName", "Swagger on Windows", "deviceType", "WEB"),
                    "400", "401", "409", "503");
            describe(api, "/auth/login", PathItem.HttpMethod.POST, "Authentication", "Sign in with password and email OTP",
                    "Public. Request a fresh LOGIN OTP using the user's email first. Use your DEV_SEED_PASSWORD for fixtures. "
                            + "A repeated login replaces the session for this user/installation only. Default: 10 attempts per 15 minutes.",
                    "200", true, Map.of("usernameOrEmail", "alice.demo@example.test", "password", "YOUR_DEV_SEED_PASSWORD",
                            "otpCode", "123456", "deviceFingerprint", "swagger-alice-001",
                            "deviceName", "Swagger on Windows", "deviceType", "WEB"), "400", "401", "429", "503");
            describe(api, "/auth/refresh", PathItem.HttpMethod.POST, "Authentication", "Rotate the token pair",
                    "Public route; the JSON refresh token authorizes renewal. Save both replacements. "
                            + "Reusing the old refresh token revokes the entire session. Refresh does not extend absolute session expiry.",
                    "200", true, Map.of("refreshToken", "PASTE_CURRENT_REFRESH_TOKEN"), "400", "401", "503");
            describe(api, "/auth/me", PathItem.HttpMethod.GET, "Authentication", "Read current user and session",
                    "Requires an access token. Returns identity, roles, and sessionId; no credentials.",
                    "200", false, null, "401");
            describe(api, "/auth/logout", PathItem.HttpMethod.POST, "Authentication", "Revoke the current session",
                    "Requires an unexpired access token. Revokes access and refresh use for this session. "
                            + "No body. Clear the saved token in Swagger's Authorize dialog afterward.",
                    "200", false, null, "401", "503");
            describe(api, "/accounts", PathItem.HttpMethod.POST, "Accounts", "Open a zero-balance account",
                    "Customer only. initialDeposit must be zero. Account creation has no idempotency contract; "
                            + "refresh your account list after an uncertain response before submitting again.",
                    "201", false, Map.of("accountType", "SAVINGS", "currency", "USD", "initialDeposit", 0),
                    "400", "401", "403", "409", "503");
            describe(api, "/accounts/me", PathItem.HttpMethod.GET, "Accounts", "List your accounts",
                    "Customer only. data is an array, including [] for no accounts. Zero-based page; size 1–100.",
                    "200", false, null, "400", "401", "403");
            describe(api, "/accounts/{accountNumber}", PathItem.HttpMethod.GET, "Accounts", "Read your account",
                    "Customer only. A missing or another customer's account returns 404.",
                    "200", false, null, "401", "403", "404");
            describe(api, "/accounts/{accountNumber}/status", PathItem.HttpMethod.PATCH, "Staff demo tools", "Change account status",
                    "ADMIN or BANK_EMPLOYEE only. Status: ACTIVE, FROZEN, CLOSED. Customers cannot freeze or reactivate accounts.",
                    "200", false, Map.of("status", "FROZEN"), "400", "401", "403", "404", "409", "503");
            describe(api, "/transactions/transfer", PathItem.HttpMethod.POST, "Transactions", "Transfer between internal accounts",
                    "Customer only; source must be yours, both accounts active and in the same currency. "
                            + "USD allows 2 decimals; KHR whole units. Fee is currently zero. "
                            + "Idempotency-Key is required: reuse the same key and identical payload after a lost response. "
                            + "A new transfer intent needs a new key; changed payload with a used key returns 409.",
                    "200", false, Map.of("sourceAccountNumber", "9000000001", "destinationAccountNumber", "9000000002",
                            "amount", new BigDecimal("25.00"), "currency", "USD", "remark", "Foundation demo"),
                    "400", "401", "403", "404", "409", "503");
            describe(api, "/transactions/deposit", PathItem.HttpMethod.POST, "Staff demo tools", "Add staff-controlled demo funds",
                    "ADMIN or BANK_EMPLOYEE only. Idempotency-Key required with the same retry rules as transfers. "
                            + "For the foundation this is local demo funding, not verified external settlement.",
                    "200", false, Map.of("accountNumber", "9000000001", "amount", new BigDecimal("100.00"),
                            "currency", "USD", "remark", "Local demo funding"), "400", "401", "403", "404", "409", "503");
            describe(api, "/transactions/account/{accountNumber}", PathItem.HttpMethod.GET, "Transactions", "Read your account history",
                    "Customer only. data.content is an array; pagination fields include pageNo, pageSize, totalElements, "
                            + "totalPages, last. Zero-based page; size 1–100. Missing or foreign account returns 404.",
                    "200", false, null, "400", "401", "403", "404");
            describe(api, "/transactions/{referenceNumber}", PathItem.HttpMethod.GET, "Transactions", "Read a transaction by reference",
                    "Customer only. You must own its source or destination account; otherwise returns 404.",
                    "200", false, null, "401", "403", "404");
            describe(api, "/transactions/search", PathItem.HttpMethod.GET, "Transactions", "Search your transactions",
                    "Customer only. Cursor pagination, size 1–50 (default 20); filters: currency, accountNumber, month, from/to dates, amount, direction IN/OUT, type, status, reference. "
                    + "Ownership is always applied. Date ranges are inclusive in Asia/Phnom_Penh and limited to 366 days; default current month. Amount requires USD/KHR; USD cents, KHR whole units. Foreign account matches return an empty list.",
                    "200",false,null,"400","401","403");
        };
    }

    private void describe(OpenAPI api, String suffix, PathItem.HttpMethod method, String tag, String summary,
                          String description, String successCode, boolean publicAccess, Map<String, Object> example,
                          String... errors) {
        String path = "/api/v1" + suffix;
        PathItem item = api.getPaths().get(path);
        if (item == null) return; // The same customizer runs for filtered groups and the full API.
        Operation operation = item.readOperationsMap().get(method);
        if (operation == null) return;
        operation.setTags(List.of(tag));
        operation.setSummary(summary);
        operation.setDescription(description);
        if (publicAccess) operation.setSecurity(List.of()); // Explicitly override inherited bearer security.
        ApiResponse success = operation.getResponses().get(successCode);
        if (success == null) success = operation.getResponses().get("200");
        if (success == null) success = new ApiResponse();
        if (success.getContent() != null && success.getContent().containsKey("*/*")) {
            MediaType json = success.getContent().remove("*/*");
            success.getContent().addMediaType("application/json", json);
        }
        success.setDescription(successCode.equals("201") ? "Created" : "Successful operation");
        ApiResponses responses = new ApiResponses().addApiResponse(successCode, success);
        for (String status : errors) responses.addApiResponse(status, error(status, path));
        // The outer audit filter can replace even an unauthenticated/read rejection with 503.
        responses.putIfAbsent("503", error("503", path));
        responses.addApiResponse("500", error("500", path));
        operation.setResponses(responses);
        if (example != null && operation.getRequestBody() != null && operation.getRequestBody().getContent() != null)
            operation.getRequestBody().getContent().values().forEach(media -> media.setExample(example));
        if (operation.getParameters() != null) operation.getParameters().forEach(parameter -> {
            if ("Idempotency-Key".equals(parameter.getName())) {
                parameter.setRequired(true);
                parameter.setExample(suffix.endsWith("deposit") ? "swagger-deposit-001" : "swagger-transfer-001");
                parameter.setDescription("1–128 letters/digits or . _ : -; reuse only for the identical operation. "
                        + "A new operation needs a new key.");
            }
        });
    }

    private void nullable(OpenAPI api, String model, String... fields) {
        Schema<?> schema = api.getComponents().getSchemas().get(model);
        if (schema == null || schema.getProperties() == null) return;
        for (String field : fields) {
            Schema<?> property = schema.getProperties().get(field);
            if (property == null) continue;
            if (api.getSpecVersion() == SpecVersion.V31) {
                var types = new LinkedHashSet<String>();
                if (property.getTypes() != null) types.addAll(property.getTypes());
                if (property.getType() != null) types.add(property.getType());
                types.add("null");
                property.setType(null);
                property.setTypes(types);
            } else {
                property.setNullable(true);
            }
        }
    }

    private ApiResponse error(String status, String path) {
        String code = switch (status) {
            case "400" -> "VALIDATION_FAILED";
            case "401" -> path.endsWith("register") ? "OTP_INVALID"
                    : path.endsWith("login") ? "AUTHENTICATION_FAILED"
                    : path.endsWith("refresh") ? "TOKEN_INVALID" : "AUTHENTICATION_REQUIRED";
            case "403" -> "ACCESS_DENIED";
            case "404" -> "RESOURCE_NOT_FOUND";
            case "409" -> "RESOURCE_CONFLICT";
            case "429" -> path.endsWith("login") ? "LOGIN_RATE_LIMITED" : "OTP_RATE_LIMITED";
            case "503" -> path.endsWith("request-otp") ? "OTP_DELIVERY_UNAVAILABLE" : "AUDIT_UNAVAILABLE";
            default -> "INTERNAL_ERROR";
        };
        String description = switch (status) {
            case "400" -> "Invalid fields, money, currency, pagination or missing idempotency key; inspect error and fieldErrors";
            case "401" -> "Missing/invalid credentials, OTP, access/refresh token, or expired/revoked session/device";
            case "403" -> "Current role is not permitted";
            case "404" -> "Resource is missing or is not owned by the customer";
            case "409" -> "Identity/resource conflict, inactive account, idempotency conflict or concurrent update";
            case "429" -> "Rate limit reached; wait for Retry-After";
            case "503" -> "Required mail or audit storage is unavailable; try again later";
            default -> "Unexpected server error";
        };
        Map<String, Object> example = new LinkedHashMap<>(Map.of("success", false, "error", code,
                "message", description, "status", Integer.parseInt(status), "path", path,
                "timestamp", "2026-10-17T00:00:00Z", "fieldErrors", Map.of()));
        example.put("retryAfterSeconds", status.equals("429") ? 60 : null);
        ApiResponse response = new ApiResponse().description(description).content(new Content().addMediaType(
                "application/json", new MediaType().schema(new Schema<>().$ref("#/components/schemas/ApiErrorResponse"))
                        .example(example)));
        if (status.equals("429")) response.addHeaderObject("Retry-After", new Header()
                .description("Seconds before another attempt").schema(new IntegerSchema()).example(60));
        return response;
    }
}
