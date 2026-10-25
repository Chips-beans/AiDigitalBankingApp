package com.bank.digital_banking.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        final String securitySchemeName = "bearerAuth";
        return new OpenAPI()
                .info(new Info()
                        .title("Digital Banking API")
                        .version("1.0.0")
                        .description("Digital Banking & Smart Wallet API documentation. "
                                + "Select the 'all' group to inspect all modules (Auth, Accounts, Transactions, "
                                + "QR Payments, Merchants, Fraud, AI Insights, and Audit Logs), or 'foundation' "
                                + "for the core milestone delivered contracts. Public auth calls require no bearer token. "
                                + "Protected calls use an access token in Authorize (paste the token only)."))
                .addSecurityItem(new SecurityRequirement().addList(securitySchemeName))
                .components(new Components()
                        .addSecuritySchemes(securitySchemeName,
                                new SecurityScheme()
                                        .name(securitySchemeName)
                                        .type(SecurityScheme.Type.HTTP)
                                        .scheme("bearer")
                                        .bearerFormat("JWT")));
    }

    // ===================================================================
    // Added for Swagger UI: Expose all API endpoints across all modules
    // ===================================================================

    /**
     * Swagger UI Group that exposes ALL API endpoints across all controllers:
     * - Authentication & Sessions (/api/v1/auth/**)
     * - Accounts & Balances (/api/v1/accounts/**)
     * - Transactions & Deposits (/api/v1/transactions/**)
     * - QR Payments (/api/v1/payments/**)
     * - Merchant Management (/api/v1/merchants/**)
     * - Fraud Detection & Rules (/api/v1/fraud/**)
     * - AI Insights & Assistant (/api/v1/ai/**)
     * - System Audit Logs (/api/v1/audit/**)
     */
    @Bean
    public GroupedOpenApi allApi() {
        return GroupedOpenApi.builder()
                .group("all")
                .displayName("All APIs (Full Platform)")
                .pathsToMatch("/api/v1/**")
                .build();
    }

    /**
     * Swagger UI Group for Payment and Merchant services:
     * - QR Payments (/api/v1/payments/**)
     * - Merchant Onboarding & QR Config (/api/v1/merchants/**)
     */
    @Bean
    public GroupedOpenApi paymentsGroupApi() {
        return GroupedOpenApi.builder()
                .group("payments")
                .displayName("Payments & Merchants")
                .pathsToMatch("/api/v1/payments/**", "/api/v1/merchants/**")
                .build();
    }

    /**
     * Swagger UI Group for Advanced & Intelligence services:
     * - AI Insights & Chat Assistant (/api/v1/ai/**)
     * - Fraud Detection Engine (/api/v1/fraud/**)
     * - System Audit Trails (/api/v1/audit/**)
     */
    @Bean
    public GroupedOpenApi advancedServicesGroupApi() {
        return GroupedOpenApi.builder()
                .group("advanced-services")
                .displayName("AI, Fraud & Audit")
                .pathsToMatch("/api/v1/ai/**", "/api/v1/fraud/**", "/api/v1/audit/**")
                .build();
    }
}
