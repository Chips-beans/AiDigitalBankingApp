package com.bank.digital_banking.config;

import com.bank.digital_banking.common.dto.ApiErrorResponse;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.auth.security.JwtAuthenticationFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.core.userdetails.*;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.*;
import tools.jackson.databind.ObjectMapper;
import java.util.*;

@Configuration @EnableWebSecurity
public class SecurityConfig {
    @Bean public PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }

    @Bean
    public UserDetailsService userDetailsService(UserRepository users) {
        return username -> users.findByUsername(username).map(u -> User.withUsername(u.getUsername())
                .password(u.getPassword() == null ? "" : u.getPassword()).disabled(!u.isEnabled())
                .authorities(u.getRoles().stream().map(r -> r.getName().name()).toArray(String[]::new)).build())
                .orElseThrow(() -> new UsernameNotFoundException("User unavailable"));
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, JwtAuthenticationFilter jwt, ObjectMapper json,
                                                  @org.springframework.beans.factory.annotation.Qualifier("corsConfigurationSource") CorsConfigurationSource cors) throws Exception {
        http.cors(c -> c.configurationSource(cors)).csrf(AbstractHttpConfigurer::disable)
            .httpBasic(AbstractHttpConfigurer::disable).formLogin(AbstractHttpConfigurer::disable)
            .logout(AbstractHttpConfigurer::disable)
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .exceptionHandling(e -> e
                .authenticationEntryPoint((request,response,ex) -> {
                    response.setStatus(401); response.setContentType("application/json");
                    response.getWriter().write(json.writeValueAsString(ApiErrorResponse.of(401,"AUTHENTICATION_REQUIRED",
                            "Sign in to continue", request.getRequestURI(), Map.of(), null)));
                })
                .accessDeniedHandler((request,response,ex) -> {
                    response.setStatus(403); response.setContentType("application/json");
                    response.getWriter().write(json.writeValueAsString(ApiErrorResponse.of(403,"ACCESS_DENIED",
                            "You do not have permission for this action", request.getRequestURI(), Map.of(), null)));
                }))
            .authorizeHttpRequests(a -> a
                .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/v1/merchant-auth/attempts", "/api/v1/merchant-auth/exchange",
                        "/api/v1/merchant-auth/refresh", "/api/v1/merchant-auth/attempts/*/status",
                        "/api/v1/merchant-auth/attempts/*/cancel").permitAll()
                .requestMatchers("/api/v1/merchant-auth/session", "/api/v1/merchant-auth/logout").hasAuthority("MERCHANT_SESSION")
                .requestMatchers("/api/v1/merchant-auth/attempts/**", "/api/v1/auth/merchant-sessions/**").hasRole("CUSTOMER")
                .requestMatchers("/error", "/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/request-otp", "/api/v1/auth/refresh").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/v1/auth/email/request", "/api/v1/auth/email/verify",
                        "/api/v1/auth/telegram/start", "/api/v1/auth/telegram/exchange",
                        "/api/v1/auth/telegram/native/start", "/api/v1/auth/telegram/native/exchange").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/v1/auth/telegram/callback").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/v1/auth/pin/status", "/api/v1/auth/pin/setup", "/api/v1/auth/pin/unlock", "/api/v1/auth/pin/discard").permitAll()
                .requestMatchers("/api/v1/auth/pin/prepare", "/api/v1/auth/pin/change", "/api/v1/auth/pin/transfer-proof", "/api/v1/auth/profile/details").authenticated()
                .requestMatchers("/api/v1/auth/profile/photo").authenticated()
                .requestMatchers("/api/v1/auth/profile", "/api/v1/auth/email/link/request",
                        "/api/v1/auth/email/link/verify", "/api/v1/auth/telegram/link/start",
                        "/api/v1/auth/telegram/native/link/start").authenticated()
                .requestMatchers("/api/v1/auth/me", "/api/v1/auth/logout").authenticated()
                .requestMatchers(HttpMethod.PATCH, "/api/v1/accounts/*/status").hasAnyRole("ADMIN", "BANK_EMPLOYEE")
                .requestMatchers("/api/v1/accounts/**").hasRole("CUSTOMER")
                .requestMatchers("/api/v1/transactions/deposit").hasAnyRole("ADMIN", "BANK_EMPLOYEE")
                .requestMatchers("/api/v1/transactions/**", "/api/v1/ai/**").hasRole("CUSTOMER")
                .requestMatchers("/api/v1/audit/**").hasRole("ADMIN")
                .requestMatchers("/api/v1/fraud/**").hasAnyRole("ADMIN", "BANK_EMPLOYEE")
                .requestMatchers(HttpMethod.POST, "/api/v1/merchants/register").hasAnyRole("ADMIN", "CUSTOMER", "MERCHANT")
                .requestMatchers("/api/v1/merchants/**").hasAnyRole("ADMIN", "MERCHANT")
                .requestMatchers("/api/v1/analytics/monthly-overview").hasRole("CUSTOMER")
                .requestMatchers("/api/v1/analytics/**").hasAnyRole("CUSTOMER", "ADMIN")
                // Provider verification is a payment-phase prerequisite; users cannot confirm payments themselves.
                .requestMatchers("/api/v1/payments/webhook").denyAll()
                .requestMatchers("/api/v1/payments/**").hasAnyRole("ADMIN", "CUSTOMER", "MERCHANT")
                .anyRequest().denyAll())
            .addFilterBefore(jwt, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource(
            @Value("${app.cors.allowed-origins:http://localhost:8081}") String origins) {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(Arrays.stream(origins.split(",")).map(String::trim).toList());
        config.setAllowedMethods(List.of("GET","POST","PUT","PATCH","DELETE","OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization","Content-Type","Idempotency-Key","X-Merchant-Handoff"));
        config.setExposedHeaders(List.of("Retry-After", "X-Correlation-ID"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
