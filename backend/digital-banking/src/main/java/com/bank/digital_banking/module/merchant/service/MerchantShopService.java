package com.bank.digital_banking.module.merchant.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.common.util.ImageNormalizer;
import com.bank.digital_banking.module.account.service.AccountService;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthService;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.*;

import static com.bank.digital_banking.module.merchant.dto.MerchantShopDtos.*;

/**
 * Self-service shop onboarding (M4). Every operation first locks the owner through the
 * Merchant session check, so registration, edits and logo attachment serialize per owner.
 */
@Service @RequiredArgsConstructor
public class MerchantShopService {
    /** Server allowlist; the app shows localized labels for these codes. */
    public static final Map<String, String> CATEGORIES = Collections.unmodifiableMap(new LinkedHashMap<>() {{
        put("FOOD_DRINK", "5814"); put("GROCERY", "5411"); put("RETAIL", "5399"); put("FASHION", "5651");
        put("BEAUTY", "7230"); put("ELECTRONICS", "5732"); put("HEALTH", "5912"); put("SERVICES", "7299");
        put("EDUCATION", "8299"); put("TRANSPORT", "4121"); put("OTHER", "5999");
    }});
    static final int LOGO_EDGE = 512, STAGED_LOGOS_KEPT = 5;
    private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcTemplate jdbc;
    private final UserRepository users;
    private final MerchantAuthService sessions;
    private final AccountService accounts;
    private final MerchantOnboardingPolicy policy;
    private final AuditTrail audit;

    private record ShopRow(long id, String code, String name, String category, String phone, String city,
                           String address, String description, String status, long version, LocalDateTime created) {}
    private record Fields(String storeName, String category, String phone, String city, String address,
                          String description, UUID logo) {
        String canonical() {
            return String.join("\u001F", storeName, category, phone, city, address,
                    Objects.toString(description, ""), Objects.toString(logo, ""));
        }
    }

    @Transactional
    public Profile read(User user, UUID sid) {
        sessions.merchant(user, sid);
        return profile(owner(user));
    }

    @Transactional
    public Registered register(User user, UUID sid, String key, Registration request) {
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}"))
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required");
        Fields fields = new Fields(name(request.getStoreName()), category(request.getCategoryCode()), phone(request.getPhone()),
                line(request.getCity(), 100), line(request.getAddress(), 255), description(request.getDescription()),
                request.getStagedLogoId());
        sessions.merchant(user, sid);
        User owner = owner(user);
        String keyHash = HashUtils.sha256(key), requestHash = HashUtils.sha256(fields.canonical());
        var prior = jdbc.queryForList("SELECT request_hash FROM merchant_registration_requests WHERE owner_user_id=? AND key_hash=?",
                String.class, owner.getId(), keyHash);
        if (!prior.isEmpty()) {
            if (!prior.getFirst().equals(requestHash)) throw new ApiException(HttpStatus.CONFLICT,
                    "MERCHANT_REGISTRATION_CONFLICT", "This registration key was already used with different details");
            return new Registered(false, profile(owner));
        }
        if (jdbc.queryForObject("SELECT count(*) FROM merchants WHERE owner_user_id=?", Long.class, owner.getId()) > 0)
            throw new ApiException(HttpStatus.CONFLICT, "MERCHANT_ALREADY_REGISTERED", "This owner already has a shop");
        if (fields.logo() != null) lockStagedLogo(owner.getId(), fields.logo());

        String code = merchantCode();
        Long merchantId = jdbc.queryForObject("""
                INSERT INTO merchants(merchant_id,store_name,bakong_account_id,merchant_city,mcc,status,owner_user_id,
                    onboarding,category_code,business_phone,address,description)
                VALUES (?,?,?,?,?,CAST(? AS merchant_status),?,'SELF_SERVICE',?,?,?,?) RETURNING id
                """, Long.class, code, fields.storeName(), "m." + code.substring(4).toLowerCase(Locale.ROOT) + "@kesor",
                fields.city(), CATEGORIES.get(fields.category()), policy.initialStatus(), owner.getId(),
                fields.category(), fields.phone(), fields.address(), fields.description());
        accounts.openMerchantWallets(owner, merchantId);
        if (fields.logo() != null) attachLogo(merchantId, fields.logo());
        jdbc.update("INSERT INTO merchant_registration_requests(owner_user_id,key_hash,request_hash,merchant_id) VALUES (?,?,?,?)",
                owner.getId(), keyHash, requestHash, merchantId);
        audit.successAs(owner, "MERCHANT", "SHOP_REGISTERED", code);
        return new Registered(true, profile(owner));
    }

    @Transactional
    public Profile update(User user, UUID sid, ProfileUpdate request) {
        if (request.getStagedLogoId() != null && Boolean.TRUE.equals(request.getRemoveLogo()))
            throw new IllegalArgumentException("Choose a new logo or remove it, not both");
        sessions.merchant(user, sid);
        User owner = owner(user);
        var shops = jdbc.query("SELECT id,status::text,profile_version FROM merchants WHERE owner_user_id=? ORDER BY id LIMIT 2 FOR UPDATE",
                (r, i) -> new long[]{r.getLong(1), "ACTIVE".equals(r.getString(2)) || "PENDING".equals(r.getString(2)) ? 1 : 0, r.getLong(3)},
                owner.getId());
        if (shops.isEmpty()) throw new ApiException(HttpStatus.CONFLICT, "MERCHANT_REGISTRATION_REQUIRED", "Register a shop first");
        if (shops.size() > 1) throw new ApiException(HttpStatus.CONFLICT, "MERCHANT_RECOVERY_REQUIRED", "This shop needs support review");
        long id = shops.getFirst()[0];
        if (shops.getFirst()[1] == 0) throw new ApiException(HttpStatus.FORBIDDEN, "MERCHANT_INACTIVE", "This shop cannot be changed right now");
        if (shops.getFirst()[2] != request.getVersion()) throw new ApiException(HttpStatus.CONFLICT,
                "MERCHANT_PROFILE_CONFLICT", "The shop profile changed; reload and try again");

        var sets = new ArrayList<String>();
        var values = new ArrayList<Object>();
        if (request.getStoreName() != null) { sets.add("store_name=?"); values.add(name(request.getStoreName())); }
        if (request.getCategoryCode() != null) {
            String category = category(request.getCategoryCode());
            sets.add("category_code=?"); values.add(category);
            sets.add("mcc=?"); values.add(CATEGORIES.get(category));
        }
        if (request.getPhone() != null) { sets.add("business_phone=?"); values.add(phone(request.getPhone())); }
        if (request.getCity() != null) { sets.add("merchant_city=?"); values.add(line(request.getCity(), 100)); }
        if (request.getAddress() != null) { sets.add("address=?"); values.add(line(request.getAddress(), 255)); }
        if (request.getDescription() != null) { sets.add("description=?"); values.add(description(request.getDescription())); }
        if (request.getStagedLogoId() != null) lockStagedLogo(owner.getId(), request.getStagedLogoId());
        boolean removeLogo = Boolean.TRUE.equals(request.getRemoveLogo());
        if (sets.isEmpty() && request.getStagedLogoId() == null && !removeLogo) return profile(owner);

        sets.add("profile_version=profile_version+1");
        sets.add("updated_at=NOW()");
        values.add(id);
        jdbc.update("UPDATE merchants SET " + String.join(",", sets) + " WHERE id=?", values.toArray());
        if (request.getStagedLogoId() != null) attachLogo(id, request.getStagedLogoId());
        else if (removeLogo) jdbc.update("DELETE FROM merchant_logos WHERE merchant_id=? AND status='ATTACHED'", id);
        audit.successAs(owner, "MERCHANT", "SHOP_PROFILE_UPDATED", Long.toString(id));
        return profile(owner);
    }

    @Transactional
    public StagedLogo stageLogo(User user, UUID sid, MultipartFile file) {
        if (file != null && file.getSize() > ImageNormalizer.MAX_BYTES)
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "MERCHANT_LOGO_TOO_LARGE", "Choose a JPG or PNG logo up to 5 MB");
        ImageNormalizer.Image image;
        try { image = ImageNormalizer.normalize(file, LOGO_EDGE); }
        catch (IllegalArgumentException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MERCHANT_LOGO_INVALID", "Choose a valid JPG or PNG up to 5 MB and 16 megapixels");
        }
        sessions.merchant(user, sid);
        UUID id = UUID.randomUUID();
        OffsetDateTime created = jdbc.queryForObject("""
                INSERT INTO merchant_logos(id,owner_user_id,content_type,image_data,width,height) VALUES (?,?,?,?,?,?)
                RETURNING created_at
                """, OffsetDateTime.class, id, user.getId(), image.contentType(), image.data(), image.width(), image.height());
        // Bound abandoned uploads per owner; the scheduled sweep removes the rest after a day.
        jdbc.update("""
                DELETE FROM merchant_logos WHERE id IN (SELECT id FROM merchant_logos WHERE owner_user_id=? AND status='STAGED'
                    ORDER BY created_at DESC, id OFFSET ?)
                """, user.getId(), STAGED_LOGOS_KEPT);
        return new StagedLogo(id, image.contentType(), image.width(), image.height(), created.plusDays(1));
    }

    @Transactional
    public Logo logo(User user, UUID sid) {
        sessions.merchant(user, sid);
        return jdbc.query("""
                SELECT l.content_type,l.image_data FROM merchant_logos l JOIN merchants m ON m.id=l.merchant_id
                WHERE m.owner_user_id=? AND l.status='ATTACHED' ORDER BY m.id LIMIT 1
                """, (r, i) -> new Logo(r.getString(1), r.getBytes(2)), user.getId()).stream().findFirst()
                .orElseThrow(() -> new com.bank.digital_banking.common.exception.ResourceNotFoundException("Logo not available"));
    }

    @Scheduled(fixedDelay = 600000, initialDelay = 120000)
    @Transactional
    public void sweepStagedLogos() {
        jdbc.update("""
                DELETE FROM merchant_logos WHERE id IN (SELECT id FROM merchant_logos WHERE status='STAGED'
                    AND created_at < CURRENT_TIMESTAMP - INTERVAL '1 day' LIMIT 200 FOR UPDATE SKIP LOCKED)
                """);
    }

    private User owner(User user) {
        return users.findById(user.getId()).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                "SESSION_INVALID", "Session is expired or revoked"));
    }

    private Profile profile(User owner) {
        var shops = jdbc.query("""
                SELECT id,merchant_id,store_name,category_code,business_phone,merchant_city,address,description,
                    status::text,profile_version,created_at FROM merchants WHERE owner_user_id=? ORDER BY id LIMIT 2
                """, (r, i) -> new ShopRow(r.getLong(1), r.getString(2), r.getString(3), r.getString(4), r.getString(5),
                r.getString(6), r.getString(7), r.getString(8), r.getString(9), r.getLong(10),
                r.getObject(11, LocalDateTime.class)), owner.getId());
        var person = new Owner(owner.getId(), Objects.toString(owner.getFirstName(), "").strip());
        if (shops.isEmpty()) return new Profile("SHOP_REQUIRED", person, null, List.of());
        if (shops.size() > 1) return new Profile("RECOVERY_REQUIRED", person, null, List.of());
        ShopRow s = shops.getFirst();
        String logo = jdbc.queryForList("SELECT id::text FROM merchant_logos WHERE merchant_id=? AND status='ATTACHED'",
                String.class, s.id()).stream().findFirst().orElse(null);
        var wallets = jdbc.query("""
                SELECT account_number,currency,status,balance FROM accounts WHERE merchant_id=? AND account_category='MERCHANT'
                ORDER BY CASE currency WHEN 'KHR' THEN 0 ELSE 1 END, id
                """, (r, i) -> new Wallet(r.getString(1), "MERCHANT", s.code(), r.getString(2), r.getString(3),
                money(r.getBigDecimal(4), r.getString(2))), s.id());
        var shop = new Shop(s.code(), s.name(), s.category(), s.phone(), s.city(), s.address(), s.description(),
                s.status(), logo, s.version(), s.created() == null ? null : s.created().atZone(ZoneId.systemDefault()).toOffsetDateTime());
        return new Profile("ACTIVE".equals(s.status()) ? "READY" : "RESTRICTED", person, shop, wallets);
    }

    private void lockStagedLogo(long owner, UUID logo) {
        var found = jdbc.queryForList("SELECT owner_user_id FROM merchant_logos WHERE id=? AND status='STAGED' FOR UPDATE", Long.class, logo);
        if (found.isEmpty() || found.getFirst() != owner) throw new ApiException(HttpStatus.BAD_REQUEST,
                "MERCHANT_LOGO_INVALID", "Upload the logo again");
    }

    private void attachLogo(long merchant, UUID logo) {
        jdbc.update("DELETE FROM merchant_logos WHERE merchant_id=? AND status='ATTACHED'", merchant);
        jdbc.update("UPDATE merchant_logos SET status='ATTACHED',merchant_id=?,attached_at=CURRENT_TIMESTAMP WHERE id=? AND status='STAGED'",
                merchant, logo);
    }

    private String merchantCode() {
        for (int attempt = 0; attempt < 20; attempt++) {
            var code = new StringBuilder("MCH-");
            for (int i = 0; i < 8; i++) code.append(CODE_ALPHABET.charAt(RANDOM.nextInt(CODE_ALPHABET.length())));
            if (jdbc.queryForObject("SELECT count(*) FROM merchants WHERE merchant_id=?", Long.class, code.toString()) == 0)
                return code.toString();
        }
        throw new IllegalStateException("Merchant code allocation failed");
    }

    static String money(BigDecimal value, String currency) {
        return value.setScale("KHR".equals(currency) ? 0 : 2, RoundingMode.DOWN).toPlainString();
    }

    static String name(String raw) { return line(raw, 150); }

    static String line(String raw, int max) {
        String value = raw == null ? "" : raw.strip().replaceAll("\\s+", " ");
        if (value.isEmpty() || value.length() > max || value.chars().anyMatch(Character::isISOControl))
            throw new IllegalArgumentException("Invalid text field");
        return value;
    }

    static String description(String raw) {
        if (raw == null || raw.isBlank()) return null;
        String value = raw.strip().replace("\r\n", "\n");
        if (value.length() > 500 || value.chars().anyMatch(c -> c != '\n' && Character.isISOControl(c)))
            throw new IllegalArgumentException("Invalid description");
        return value;
    }

    static String category(String raw) {
        String value = raw == null ? "" : raw.strip().toUpperCase(Locale.ROOT);
        if (!CATEGORIES.containsKey(value)) throw new ApiException(HttpStatus.BAD_REQUEST,
                "MERCHANT_CATEGORY_INVALID", "Choose a supported business category");
        return value;
    }

    /** Normalizes to E.164. Cambodian local numbers (0XX...) become +855. */
    static String phone(String raw) {
        String value = raw == null ? "" : raw.strip().replaceAll("[\\s().-]", "");
        if (value.startsWith("00")) value = "+" + value.substring(2);
        else if (value.startsWith("0")) value = "+855" + value.substring(1);
        else if (value.startsWith("855")) value = "+" + value;
        if (!value.matches("\\+[1-9][0-9]{7,14}") || (value.startsWith("+855") && !value.matches("\\+855[1-9][0-9]{7,8}")))
            throw new ApiException(HttpStatus.BAD_REQUEST, "MERCHANT_PHONE_INVALID", "Enter a valid business phone number");
        return value;
    }
}
