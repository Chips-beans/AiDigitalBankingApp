package com.bank.digital_banking.common.util;

import org.springframework.web.multipart.MultipartFile;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.MemoryCacheImageInputStream;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Locale;

/** Decodes an uploaded JPG/PNG and re-encodes it bounded; input metadata is never kept. */
public final class ImageNormalizer {
    public static final int MAX_BYTES = 5 * 1024 * 1024;
    public static final long MAX_PIXELS = 16_000_000L;
    private ImageNormalizer() {}

    public record Image(byte[] data, String contentType, int width, int height) {}

    /** @throws IllegalArgumentException for anything that is not a bounded JPG/PNG. */
    public static Image normalize(MultipartFile file, int maxEdge) {
        if (file == null || file.isEmpty() || file.getSize() > MAX_BYTES) throw new IllegalArgumentException("image");
        // Dimensions are checked before decoding.
        try (var input = new MemoryCacheImageInputStream(file.getInputStream())) {
            var readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) throw new IllegalArgumentException("image");
            ImageReader reader = readers.next();
            try {
                String format = reader.getFormatName().toLowerCase(Locale.ROOT);
                if (!format.equals("png") && !format.equals("jpeg")) throw new IllegalArgumentException("image");
                reader.setInput(input, true, true);
                int width = reader.getWidth(0), height = reader.getHeight(0);
                if (width < 1 || height < 1 || (long) width * height > MAX_PIXELS) throw new IllegalArgumentException("image");
                BufferedImage decoded = reader.read(0);
                double scale = Math.min(1.0, (double) maxEdge / Math.max(width, height));
                var image = new BufferedImage(Math.max(1, (int) (width * scale)), Math.max(1, (int) (height * scale)),
                        format.equals("png") ? BufferedImage.TYPE_INT_ARGB : BufferedImage.TYPE_INT_RGB);
                var graphics = image.createGraphics();
                try {
                    graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
                    graphics.drawImage(decoded, 0, 0, image.getWidth(), image.getHeight(), null);
                } finally { graphics.dispose(); decoded.flush(); }
                var output = new ByteArrayOutputStream();
                try {
                    if (!ImageIO.write(image, format, output)) throw new IllegalArgumentException("image");
                    byte[] normalized = output.toByteArray();
                    if (normalized.length == 0 || normalized.length > MAX_BYTES) throw new IllegalArgumentException("image");
                    return new Image(normalized, format.equals("png") ? "image/png" : "image/jpeg",
                            image.getWidth(), image.getHeight());
                } finally { image.flush(); }
            } finally { reader.dispose(); }
        } catch (IOException ex) { throw new IllegalArgumentException("image", ex); }
    }
}
