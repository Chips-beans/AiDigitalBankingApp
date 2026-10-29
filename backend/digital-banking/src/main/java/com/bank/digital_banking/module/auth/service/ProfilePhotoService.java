package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.MemoryCacheImageInputStream;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.*;
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
        if (file.isEmpty() || file.getSize() > MAX_BYTES) throw invalid();
        byte[] normalized;
        String contentType;
        // Dimensions are checked before decoding; input metadata is never stored.
        try (var input = new MemoryCacheImageInputStream(file.getInputStream())) {
            var readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) throw invalid();
            ImageReader reader = readers.next();
            try {
                String format = reader.getFormatName().toLowerCase(java.util.Locale.ROOT);
                if (!format.equals("png") && !format.equals("jpeg")) throw invalid();
                reader.setInput(input, true, true);
                int width = reader.getWidth(0), height = reader.getHeight(0);
                if (width < 1 || height < 1 || (long) width * height > 16_000_000) throw invalid();
                BufferedImage decoded = reader.read(0);
                double scale = Math.min(1.0, 1024.0 / Math.max(width, height));
                var image = new BufferedImage(Math.max(1, (int) (width * scale)), Math.max(1, (int) (height * scale)),
                        format.equals("png") ? BufferedImage.TYPE_INT_ARGB : BufferedImage.TYPE_INT_RGB);
                var graphics = image.createGraphics();
                try {
                    graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
                    graphics.drawImage(decoded, 0, 0, image.getWidth(), image.getHeight(), null);
                } finally { graphics.dispose(); decoded.flush(); }
                var output = new ByteArrayOutputStream();
                try {
                    if (!ImageIO.write(image, format, output)) throw invalid();
                    normalized = output.toByteArray();
                } finally { image.flush(); }
                contentType = format.equals("png") ? "image/png" : "image/jpeg";
            } finally { reader.dispose(); }
        } catch (IOException | IllegalArgumentException ex) { throw invalid(); }
        if (normalized.length == 0 || normalized.length > MAX_BYTES) throw invalid();
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
