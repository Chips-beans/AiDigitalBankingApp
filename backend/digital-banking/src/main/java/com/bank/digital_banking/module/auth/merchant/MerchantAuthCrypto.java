package com.bank.digital_banking.module.auth.merchant;

import com.bank.digital_banking.common.util.HashUtils;
import javax.crypto.*;
import javax.crypto.spec.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;

final class MerchantAuthCrypto {
    private static final SecureRandom RANDOM = new SecureRandom();
    private MerchantAuthCrypto() {}
    static String random() {
        byte[] value = new byte[32]; RANDOM.nextBytes(value);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }
    static boolean matches(String hash, String raw) {
        return hash != null && raw != null && MessageDigest.isEqual(hash.getBytes(StandardCharsets.US_ASCII),
                HashUtils.sha256(raw).getBytes(StandardCharsets.US_ASCII));
    }
    static String challenge(String verifier) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(HexFormat.of().parseHex(HashUtils.sha256(verifier)));
    }
    static String developmentKey(String secret) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(Base64.getDecoder().decode(secret), "HmacSHA256"));
            return Base64.getEncoder().encodeToString(mac.doFinal("kesor-merchant-recovery-v1".getBytes(StandardCharsets.US_ASCII)));
        } catch (GeneralSecurityException e) { throw new IllegalStateException("Merchant encryption unavailable"); }
    }
    static String seal(String key, UUID attempt, String json) { return crypt(true, key, attempt, json); }
    static String open(String key, UUID attempt, String ciphertext) { return crypt(false, key, attempt, ciphertext); }
    private static String crypt(boolean encrypt, String key, UUID attempt, String input) {
        try {
            byte[] data = encrypt ? input.getBytes(StandardCharsets.UTF_8) : Base64.getDecoder().decode(input);
            byte[] iv = new byte[12];
            if (encrypt) RANDOM.nextBytes(iv);
            else { if (data.length < 28) throw new IllegalArgumentException(); System.arraycopy(data, 0, iv, 0, 12); }
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(encrypt ? Cipher.ENCRYPT_MODE : Cipher.DECRYPT_MODE,
                    new SecretKeySpec(Base64.getDecoder().decode(key), "AES"), new GCMParameterSpec(128, iv));
            cipher.updateAAD(("kesor-merchant-recovery-v1:" + attempt).getBytes(StandardCharsets.US_ASCII));
            if (!encrypt) return new String(cipher.doFinal(data, 12, data.length - 12), StandardCharsets.UTF_8);
            byte[] encrypted = cipher.doFinal(data), result = new byte[12 + encrypted.length];
            System.arraycopy(iv, 0, result, 0, 12); System.arraycopy(encrypted, 0, result, 12, encrypted.length);
            return Base64.getEncoder().encodeToString(result);
        } catch (GeneralSecurityException | IllegalArgumentException e) { throw new IllegalStateException("Merchant recovery unavailable"); }
    }
}
