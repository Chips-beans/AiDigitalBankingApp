package com.bank.digital_banking.module.payment.adapter;

import kh.gov.nbc.bakong_khqr.BakongKHQR;
import kh.gov.nbc.bakong_khqr.model.IndividualInfo;
import kh.gov.nbc.bakong_khqr.model.KHQRCurrency;
import kh.gov.nbc.bakong_khqr.model.KHQRData;
import kh.gov.nbc.bakong_khqr.model.KHQRResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Map;

@Component
public class BakongAdapter {

    private final RestClient restClient;

    public BakongAdapter(BakongProperties properties) {
        this.restClient = RestClient.builder()
                .baseUrl(properties.getUrl())
                .defaultHeader(HttpHeaders.AUTHORIZATION, "Bearer " + properties.getToken())
                .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .build();
    }

    public KHQRData generateIndividualKhqr(String bakongAccountId, String merchantName, double amount, String currency) {
        IndividualInfo individualInfo = new IndividualInfo();
        individualInfo.setBakongAccountId(bakongAccountId);
        individualInfo.setAccountInformation(merchantName);
        individualInfo.setAcquiringBank("Digital Bank");
        
        // 1. Use Bakong KHQRCurrency Enum instead of String "840"/"116"
        individualInfo.setCurrency("USD".equalsIgnoreCase(currency) ? KHQRCurrency.USD : KHQRCurrency.KHR);
        individualInfo.setAmount(amount);

        // 2. Call SDK generator method
        KHQRResponse<KHQRData> response = BakongKHQR.generateIndividual(individualInfo);
        
        // 3. Use response.getData() instead of response.getKhqrData()
        if (response != null && response.getData() != null) {
            return response.getData();
        }
        
        throw new RuntimeException("Failed to generate KHQR code string via Bakong SDK");
    }
    public boolean checkTransactionByMd5(String md5Hash) {
        Map<String, String> requestBody = Map.of("md5", md5Hash);

        try {
            Map<?, ?> response = restClient.post()
                    .uri("/v1/check_transaction_by_md5")
                    .body(requestBody)
                    .retrieve()
                    .body(Map.class);

            if (response != null && response.containsKey("responseCode")) {
                Object code = response.get("responseCode");
                return Integer.valueOf(0).equals(code) || "0".equals(String.valueOf(code));
            }
        } catch (Exception e) {
            return false;
        }
        return false;
    }
}