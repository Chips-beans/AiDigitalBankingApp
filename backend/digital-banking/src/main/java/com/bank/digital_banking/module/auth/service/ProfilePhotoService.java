package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.ImageNormalizer;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.Base64;

@Service @RequiredArgsConstructor
public class ProfilePhotoService {
    public static final int MAX_BYTES = 5 * 1024 * 1024;
    private final JdbcTemplate jdbc;
    private final UserRepository users;
    private final ContinuationPersistence continuation;
    private final AuditTrail audit;

    public record Photo(String contentType, String imageBase64) {}

    @Transactional(readOnly = true)
    public Photo read(User user) {
        continuation.requireCustomer(user);
        return jdbc.query("SELECT content_type, image_data FROM customer_profile_photos WHERE user_id = ?",
                (row, index) -> new Photo(row.getString(1), Base64.getEncoder().encodeToString(row.getBytes(2))),
                user.getId()).stream().findFirst().orElse(null);
    }

    @Transactional
    public Photo save(User authenticated, MultipartFile file) {
        continuation.requireCustomer(authenticated);
        ImageNormalizer.Image image;
        try { image = ImageNormalizer.normalize(file, 1024); }
        catch (IllegalArgumentException ex) { throw invalid(); }
        byte[] normalized = image.data();
        String contentType = image.contentType();
        User user = users.findLockedById(authenticated.getId()).orElseThrow(this::invalid);
        continuation.requireCustomer(user);
        jdbc.update("""
                INSERT INTO customer_profile_photos(user_id, content_type, image_data) VALUES (?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET content_type = EXCLUDED.content_type,
                    image_data = EXCLUDED.image_data, updated_at = CURRENT_TIMESTAMP
                """, user.getId(), contentType, normalized);
        audit.successAs(user, "PROFILE", "PHOTO_UPDATED", user.getId().toString());
        return new Photo(contentType, Base64.getEncoder().encodeToString(normalized));
    }

    private ApiException invalid() {
        return new ApiException(HttpStatus.BAD_REQUEST, "PROFILE_PHOTO_INVALID",
                "Choose a valid JPG or PNG up to 5 MB and 16 megapixels");
    }
}
