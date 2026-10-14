package com.bank.digital_banking.module.payment.adapter;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Data
@Configuration
@ConfigurationProperties(prefix = "bakong.api")
public class BakongProperties {
    private String url;
    private String token;
    private String merchantName;
    private String merchantCity;
}