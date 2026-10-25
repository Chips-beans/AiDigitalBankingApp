package com.bank.digital_banking.module.payment.qr;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app.qr")
@Getter
@Setter
public class QrProperties {

    /** Default display merchant/bank name when not specified */
    private String merchantName = "Digital Bank";

    /** Default city */
    private String merchantCity = "Phnom Penh";

    /** Acquiring bank name */
    private String acquiringBank = "Digital Bank";

    /** Country code (ISO 3166-1 alpha-2) */
    private String countryCode = "KH";

    /** Globally unique identifier for the bank */
    private String guid = "bank@digitalbank";

    /** Default currency */
    private String defaultCurrency = "USD";
}
