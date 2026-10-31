package com.bank.digital_banking.config;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.*;

@Configuration
public class MerchantAuthOpenApiConfig {
    @Bean GroupedOpenApi merchantAuthenticationApi() {
        return GroupedOpenApi.builder().group("merchant-auth").displayName("Merchant approval and sessions")
                .pathsToMatch("/api/v1/merchant-auth/**","/api/v1/auth/merchant-sessions","/api/v1/auth/merchant-sessions/**").build();
    }
}
