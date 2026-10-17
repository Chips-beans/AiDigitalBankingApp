package com.bank.digital_banking.common.util;

import com.bank.digital_banking.common.exception.ApiException;
import org.springframework.http.HttpStatus;
import java.math.BigDecimal;
import java.util.Locale;

public final class CurrencyUtils {
    public static final BigDecimal MAX_AMOUNT = new BigDecimal("9999999999999.99");
    private CurrencyUtils() { }

    public static String currency(String value) {
        String currency = value == null ? "" : value.toUpperCase(Locale.ROOT);
        if (!currency.equals("USD") && !currency.equals("KHR"))
            throw invalid("UNSUPPORTED_CURRENCY", "Currency must be USD or KHR");
        return currency;
    }

    public static BigDecimal amount(BigDecimal value, String currency, boolean allowZero) {
        currency = currency(currency);
        int scale = currency.equals("KHR") ? 0 : 2;
        if (value == null || value.signum() < 0 || (!allowZero && value.signum() == 0)
                || value.compareTo(MAX_AMOUNT) > 0 || value.stripTrailingZeros().scale() > scale)
            throw invalid("INVALID_AMOUNT", "Amount must fit the supported range and currency precision (USD: 2, KHR: 0)");
        return value.setScale(scale);
    }

    private static ApiException invalid(String code, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }
}
