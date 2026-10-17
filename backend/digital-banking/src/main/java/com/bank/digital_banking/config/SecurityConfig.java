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
                .password(u.getPassword()).disabled(!u.isEnabled())
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
                .requestMatchers("/error", "/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/request-otp", "/api/v1/auth/refresh").permitAll()
                .requestMatchers("/api/v1/auth/me", "/api/v1/auth/logout").authenticated()
                .requestMatchers(HttpMethod.PATCH, "/api/v1/accounts/*/status").hasAnyRole("ADMIN", "BANK_EMPLOYEE")
                .requestMatchers("/api/v1/accounts/**").hasRole("CUSTOMER")
                .requestMatchers("/api/v1/transactions/deposit").hasAnyRole("ADMIN", "BANK_EMPLOYEE")
                .requestMatchers("/api/v1/transactions/**", "/api/v1/ai/**").hasRole("CUSTOMER")
                .requestMatchers("/api/v1/audit/**").hasRole("ADMIN")
                .requestMatchers("/api/v1/fraud/**").hasAnyRole("ADMIN", "BANK_EMPLOYEE")
                .requestMatchers("/api/v1/merchants/**").hasAnyRole("ADMIN", "MERCHANT")
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
        config.setAllowedHeaders(List.of("Authorization","Content-Type","Idempotency-Key"));
        config.setExposedHeaders(List.of("Retry-After", "X-Correlation-ID"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
