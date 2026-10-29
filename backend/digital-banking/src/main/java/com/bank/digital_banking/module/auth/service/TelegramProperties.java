package com.bank.digital_banking.module.auth.service;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Data @Component @ConfigurationProperties(prefix = "app.telegram")
public class TelegramProperties {
    private String clientId = "";
    private String clientSecret = "";
    private String redirectUri = "";
    private String nativeRedirectUri = "";
    public boolean nativeConfigured() {
        try {
            var callback = java.net.URI.create(nativeRedirectUri);
            return clientId.matches("[0-9]+") && "https".equals(callback.getScheme())
                    && callback.getHost() != null && callback.getHost().matches("app[0-9]+-login\\.tg\\.dev")
                    && callback.getPort() == -1 && callback.getUserInfo() == null
                    && "/tglogin".equals(callback.getPath())
                    && callback.getQuery() == null && callback.getFragment() == null;
        } catch (IllegalArgumentException ex) { return false; }
    }
    private String frontendOrigin = "http://localhost:8081";
    public boolean configured() {
        try {
            var origin = java.net.URI.create(frontendOrigin);
            var callback = java.net.URI.create(redirectUri);
            boolean local = "http".equals(origin.getScheme()) && ("localhost".equals(origin.getHost()) || "127.0.0.1".equals(origin.getHost()));
            return clientId.matches("[0-9]+") && !clientSecret.isBlank() && "https".equals(callback.getScheme())
                    && callback.getHost() != null && callback.getUserInfo() == null
                    && origin.getHost() != null && origin.getUserInfo() == null
                    && frontendOrigin.equals(origin.getScheme() + "://" + origin.getAuthority())
                    && ("https".equals(origin.getScheme()) || local);
        } catch (IllegalArgumentException ex) { return false; }
    }
}
