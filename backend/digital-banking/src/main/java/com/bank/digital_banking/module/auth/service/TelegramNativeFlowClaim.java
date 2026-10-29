package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.auth.dto.ContinuationDtos.TelegramNativeExchangeRequest;
import com.bank.digital_banking.module.auth.entity.TelegramLoginFlow;
import com.bank.digital_banking.module.auth.repository.TelegramLoginFlowRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.OffsetDateTime;

@Service @RequiredArgsConstructor
public class TelegramNativeFlowClaim {
    private final TelegramLoginFlowRepository flows;

    // Commit consumption before contacting Telegram. A lost exchange response must never be replayed.
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public TelegramLoginFlow claim(TelegramNativeExchangeRequest request) {
        TelegramLoginFlow flow = flows.findLockedById(request.flowId()).orElseThrow(this::invalid);
        if (!flow.isNativeFlow() || flow.isClaimed() || flow.isCallbackHandled()
                || !flow.getExpiresAt().isAfter(OffsetDateTime.now())
                || !MessageDigest.isEqual(flow.getExchangeSecretHash().getBytes(StandardCharsets.US_ASCII),
                    HashUtils.sha256(request.exchangeSecret()).getBytes(StandardCharsets.US_ASCII))) throw invalid();
        flow.setClaimed(true);
        flow.setCallbackHandled(true);
        return flow;
    }
    private AuthenticationFailedException invalid() {
        return new AuthenticationFailedException("TELEGRAM_FLOW_INVALID", "Telegram approval expired or was already used; try again");
    }
}
