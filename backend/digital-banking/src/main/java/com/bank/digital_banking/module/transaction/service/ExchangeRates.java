package com.bank.digital_banking.module.transaction.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.CurrencyUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Fixed-rate USD/KHR conversion for internal transfers. USD to KHR is always exact;
 * KHR to USD credits are rounded down to whole cents, so the bank never credits more
 * than the debited value. Amounts never pass through floating point.
 */
@Component
public class ExchangeRates {
    private final BigDecimal khrPerUsd;

    public ExchangeRates(@Value("${app.fx.khr-per-usd:4000}") BigDecimal khrPerUsd) {
        if (khrPerUsd.signum() <= 0 || khrPerUsd.stripTrailingZeros().scale() > 0)
            throw new IllegalStateException("app.fx.khr-per-usd must be a positive whole number");
        this.khrPerUsd = khrPerUsd.setScale(4);
    }

    public record Quote(BigDecimal debitAmount, String debitCurrency, BigDecimal creditAmount, String creditCurrency,
                        BigDecimal rate, boolean converted) {}

    public BigDecimal khrPerUsd() { return khrPerUsd; }

    /** The credit for a debit of {@code amount} in {@code from}; rejects conversions that would credit nothing. */
    public Quote forDebit(BigDecimal amount, String from, String to) {
        from = CurrencyUtils.currency(from); to = CurrencyUtils.currency(to);
        amount = CurrencyUtils.amount(amount, from, false);
        if (from.equals(to)) return new Quote(amount, from, amount, to, BigDecimal.ONE.setScale(4), false);
        BigDecimal credit = from.equals("USD")
                ? amount.multiply(khrPerUsd).setScale(0, RoundingMode.UNNECESSARY)
                : amount.divide(khrPerUsd, 2, RoundingMode.DOWN);
        if (credit.signum() <= 0)
            throw new ApiException(HttpStatus.BAD_REQUEST, "AMOUNT_TOO_SMALL",
                    "The converted amount is less than the smallest unit of the receiving currency");
        return new Quote(amount, from, CurrencyUtils.amount(credit, to, false), to, khrPerUsd, true);
    }

    /** The exact debit needed to credit {@code credit} in {@code to}; used for fixed-amount QR requests. */
    public Quote forCredit(BigDecimal credit, String from, String to) {
        from = CurrencyUtils.currency(from); to = CurrencyUtils.currency(to);
        credit = CurrencyUtils.amount(credit, to, false);
        if (from.equals(to)) return forDebit(credit, from, to);
        BigDecimal debit;
        try {
            debit = to.equals("KHR") ? credit.divide(khrPerUsd, 2, RoundingMode.UNNECESSARY)
                    : credit.multiply(khrPerUsd).setScale(0, RoundingMode.UNNECESSARY);
        } catch (ArithmeticException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CONVERSION_NOT_EXACT",
                    "This fixed amount cannot be paid exactly from a " + from + " account; use a " + to + " account");
        }
        Quote quote = forDebit(debit, from, to);
        if (quote.creditAmount().compareTo(credit) != 0) throw new IllegalStateException("Inexact fixed-amount conversion");
        return quote;
    }
}
