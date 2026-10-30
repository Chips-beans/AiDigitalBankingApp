package com.bank.digital_banking;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.payment.qr.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class QrCodeEngineTests {

    @Test void khmerTextUsesUtf8LengthsAndAmountsNeverRound() {
        var generated = engine.generate(new QrCodeEngine.GenerateOptions("9000000001", "សុខ ដារ៉ា", new java.math.BigDecimal("10.25"), "USD", "អរគុណ", "reference", null, true));
        var decoded = engine.parse(generated.getQrString());
        assertThat(decoded.getAmount()).isEqualByComparingTo("10.25");
        assertThat(decoded.getRemark()).isEqualTo("អរគុណ");
        assertThatThrownBy(() -> engine.generate(new QrCodeEngine.GenerateOptions("9000000001", "Alice", new java.math.BigDecimal("1.001"), "USD", null, null, null, true))).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> engine.generate(new QrCodeEngine.GenerateOptions("9000000001", "Alice", new java.math.BigDecimal("1.1"), "KHR", null, null, null, true))).isInstanceOf(ApiException.class);
    }

    private QrCodeEngine engine;
    private QrProperties properties;

    @BeforeEach
    void setUp() {
        properties = new QrProperties();
        properties.setAcquiringBank("Digital Bank");
        properties.setMerchantName("Digital Bank");
        properties.setMerchantCity("Phnom Penh");
        properties.setCountryCode("KH");
        properties.setGuid("bank@digitalbank");
        properties.setDefaultCurrency("USD");
        engine = new QrCodeEngine(properties);
    }

    @Test
    void crc16CalculationAndVerification() {
        // Standard test payload without CRC
        String sample = "00020101021229340018bank@digitalbank011090000000010212Digital Bank520459995303840540510.505802KH5915Alice Bob Test6010Phnom Penh6304";
        String crc = Crc16Ccitt.calculate(sample);
        assertThat(crc).isNotNull().hasSize(4);

        String full = sample + crc;
        assertThat(Crc16Ccitt.verify(full)).isTrue();

        // Tampering any character in the payload invalidates the CRC
        String tampered = full.replace("10.50", "99.99");
        assertThat(Crc16Ccitt.verify(tampered)).isFalse();
    }

    @Test
    void tlvBuilderAndParserRoundTrip() {
        EmvcoTlvBuilder builder = new EmvcoTlvBuilder();
        builder.addTag("00", "01");
        builder.addTag("01", "12");
        builder.addTemplate("29", Map.of("00", "bank@digitalbank", "01", "9000000001"));
        builder.addTag("53", "840");

        String fullQr = builder.buildWithCrc();
        assertThat(fullQr).contains("000201");
        assertThat(fullQr).contains("010212");
        assertThat(fullQr).contains("6304");

        Map<String, String> parsed = EmvcoTlvParser.parse(fullQr);
        assertThat(parsed.get("00")).isEqualTo("01");
        assertThat(parsed.get("01")).isEqualTo("12");
        assertThat(parsed.get("53")).isEqualTo("840");
        assertThat(parsed.get("63")).hasSize(4);

        Map<String, String> subTags = EmvcoTlvParser.parseSubTags(parsed.get("29"));
        assertThat(subTags.get("00")).isEqualTo("bank@digitalbank");
        assertThat(subTags.get("01")).isEqualTo("9000000001");
    }

    @Test
    void generateDynamicUsdQr() {
        QrCodeEngine.GenerateOptions options = new QrCodeEngine.GenerateOptions(
                "9000000001",
                "Alice Demo",
                new BigDecimal("25.50"),
                "USD",
                "Dinner split",
                "INV-1002",
                null,
                true
        );

        EmvcoQrCode qr = engine.generate(options);

        assertThat(qr.getQrString()).isNotNull();
        assertThat(qr.getQrHash()).hasSize(32);
        assertThat(qr.isDynamic()).isTrue();
        assertThat(qr.getAccountNumber()).isEqualTo("9000000001");
        assertThat(qr.getPayeeName()).isEqualTo("Alice Demo");
        assertThat(qr.getCurrency()).isEqualTo("USD");
        assertThat(qr.getCurrencyNumericCode()).isEqualTo("840");
        assertThat(qr.getAmount()).isEqualByComparingTo("25.50");
        assertThat(qr.getCountryCode()).isEqualTo("KH");
        assertThat(qr.getMerchantCity()).isEqualTo("Phnom Penh");
        assertThat(qr.getRemark()).isEqualTo("Dinner split");
        assertThat(qr.getBillNumber()).isEqualTo("INV-1002");
        assertThat(Crc16Ccitt.verify(qr.getQrString())).isTrue();
    }

    @Test
    void generateStaticKhrQr() {
        QrCodeEngine.GenerateOptions options = new QrCodeEngine.GenerateOptions(
                "9000000002",
                "Bob Store",
                null,
                "KHR",
                "Donation",
                null,
                null,
                false
        );

        EmvcoQrCode qr = engine.generate(options);

        assertThat(qr.isDynamic()).isFalse();
        assertThat(qr.getPointOfInitiationMethod()).isEqualTo("11");
        assertThat(qr.getAccountNumber()).isEqualTo("9000000002");
        assertThat(qr.getCurrency()).isEqualTo("KHR");
        assertThat(qr.getCurrencyNumericCode()).isEqualTo("116");
        assertThat(qr.getAmount()).isNull();
        assertThat(Crc16Ccitt.verify(qr.getQrString())).isTrue();
    }

    @Test
    void parseAndValidateGeneratedQr() {
        QrCodeEngine.GenerateOptions options = new QrCodeEngine.GenerateOptions(
                "9000000003@digitalbank",
                "Charlie Cafe",
                new BigDecimal("12.00"),
                "USD",
                "Latte",
                "BILL-55",
                null,
                true
        );

        EmvcoQrCode generated = engine.generate(options);
        EmvcoQrCode decoded = engine.parse(generated.getQrString());

        assertThat(decoded.getAccountNumber()).isEqualTo("9000000003");
        assertThat(decoded.getPayeeName()).isEqualTo("Charlie Cafe");
        assertThat(decoded.getAmount()).isEqualByComparingTo("12.00");
        assertThat(decoded.getCurrency()).isEqualTo("USD");
        assertThat(decoded.isDynamic()).isTrue();
        assertThat(decoded.getRemark()).isEqualTo("Latte");
        assertThat(decoded.getBillNumber()).isEqualTo("BILL-55");
        assertThat(decoded.getQrHash()).isEqualTo(generated.getQrHash());
    }

    @Test
    void parseRejectsCorruptedCrc() {
        QrCodeEngine.GenerateOptions options = new QrCodeEngine.GenerateOptions(
                "9000000001",
                "Alice",
                new BigDecimal("10.00"),
                "USD",
                null,
                null,
                null,
                true
        );
        EmvcoQrCode qr = engine.generate(options);
        String corrupted = qr.getQrString().substring(0, qr.getQrString().length() - 2) + "00";

        assertThatThrownBy(() -> engine.parse(corrupted))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("CRC checksum validation failed");
    }

    @Test
    void parseRejectsTruncatedTlv() {
        String truncated = "00020101021229";
        assertThatThrownBy(() -> engine.parse(truncated))
                .isInstanceOf(ApiException.class);
    }
}
