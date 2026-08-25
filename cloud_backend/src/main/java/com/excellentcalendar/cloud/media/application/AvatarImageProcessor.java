package com.excellentcalendar.cloud.media.application;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Iterator;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.ImageOutputStream;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;

/**
 * Avatar image pipeline: magic-byte MIME sniffing (the declared Content-Type is not trusted),
 * JPEG EXIF orientation normalization, center-square crop, uniform JPEG output (512x512 main +
 * 128x128 thumbnail) and SHA-256 etag. JPEG/PNG decode through ImageIO; WebP through the sejda
 * imageio-webp JNI plugin. Decoding is dimension-bounded (header pixel cap + subsampled read +
 * OOM guard) so a compressed 5 MiB image cannot exhaust the heap.
 */
public final class AvatarImageProcessor {

    public static final long MAX_INPUT_BYTES = 5 * 1024 * 1024;
    public static final int MAIN_SIZE = 512;
    public static final int THUMBNAIL_SIZE = 128;
    public static final String OUTPUT_MIME_TYPE = "image/jpeg";
    private static final float JPEG_QUALITY = 0.88f;

    /**
     * Header-time pixel cap: real phone photos stay far below this, while decompression bombs
     * (tiny files claiming absurd dimensions) are rejected before any pixel allocation.
     */
    private static final long MAX_HEADER_PIXELS = 250_000_000L;

    /**
     * Allocation bound: images larger than this side are read with subsampling so the decoded
     * raster never exceeds ~4096x4096; plenty for 512x512 output.
     */
    private static final int MAX_DECODED_SIDE = 4096;

    private AvatarImageProcessor() {
    }

    public static final class UnsupportedImageTypeException extends RuntimeException {
    }

    public static final class ImageTooLargeException extends RuntimeException {
    }

    public static final class ImageProcessingException extends RuntimeException {
        public ImageProcessingException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    public record ProcessedImage(byte[] main, byte[] thumbnail, String etag, int width, int height) {
    }

    public static ProcessedImage process(byte[] input) {
        if (input == null || input.length == 0) {
            throw new UnsupportedImageTypeException();
        }
        if (input.length > MAX_INPUT_BYTES) {
            throw new ImageTooLargeException();
        }
        String mimeType = sniff(input).orElseThrow(UnsupportedImageTypeException::new);
        BufferedImage decoded = decode(input, mimeType);
        // Phone cameras store rotation in EXIF instead of the raster: normalize before cropping.
        BufferedImage oriented = "image/jpeg".equals(mimeType)
                ? JpegExifOrientation.read(input)
                        .map(orientation -> JpegExifOrientation.apply(decoded, orientation))
                        .orElse(decoded)
                : decoded;
        try {
            BufferedImage square = centerSquare(oriented);
            BufferedImage main = scale(square, MAIN_SIZE);
            BufferedImage thumbnail = scale(square, THUMBNAIL_SIZE);
            byte[] mainBytes = encodeJpeg(main);
            byte[] thumbnailBytes = encodeJpeg(thumbnail);
            return new ProcessedImage(
                    mainBytes, thumbnailBytes, sha256Hex(mainBytes), MAIN_SIZE, MAIN_SIZE);
        } catch (IOException exception) {
            throw new ImageProcessingException("image encoding failed", exception);
        }
    }

    /**
     * Detects the actual MIME type from magic bytes; only the three contract types are accepted.
     */
    public static java.util.Optional<String> sniff(byte[] bytes) {
        if (bytes.length >= 3 && (bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xFF) == 0xD8 && (bytes[2] & 0xFF) == 0xFF) {
            return java.util.Optional.of("image/jpeg");
        }
        if (bytes.length >= 8
                && (bytes[0] & 0xFF) == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G'
                && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
            return java.util.Optional.of("image/png");
        }
        if (bytes.length >= 12
                && bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F'
                && bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') {
            return java.util.Optional.of("image/webp");
        }
        return java.util.Optional.empty();
    }

    private static BufferedImage decode(byte[] bytes, String mimeType) {
        String format = switch (mimeType) {
            case "image/jpeg" -> "jpeg";
            case "image/png" -> "png";
            case "image/webp" -> "webp";
            default -> throw new UnsupportedImageTypeException();
        };
        try (ImageInputStream stream = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
            if (stream == null) {
                throw new ImageProcessingException("cannot open " + mimeType + " stream", null);
            }
            Iterator<ImageReader> byFormat = ImageIO.getImageReadersByFormatName(format);
            ImageReader reader = byFormat.hasNext() ? byFormat.next() : null;
            if (reader == null) {
                Iterator<ImageReader> byStream = ImageIO.getImageReaders(stream);
                if (!byStream.hasNext()) {
                    throw new ImageProcessingException("no decoder registered for " + mimeType, null);
                }
                reader = byStream.next();
            }
            try {
                reader.setInput(stream, true, true);
                int width = reader.getWidth(0);
                int height = reader.getHeight(0);
                if (width <= 0 || height <= 0 || (long) width * (long) height > MAX_HEADER_PIXELS) {
                    // Decompression bomb: reject on the header before any pixel allocation.
                    throw new ImageTooLargeException();
                }
                ImageReadParam param = reader.getDefaultReadParam();
                int subsample = (int) Math.max(
                        1, Math.ceil(Math.max(width, height) / (double) MAX_DECODED_SIDE));
                if (subsample > 1) {
                    param.setSourceSubsampling(subsample, subsample, 0, 0);
                }
                BufferedImage image;
                try {
                    image = reader.read(0, param);
                } catch (IllegalArgumentException exception) {
                    if (subsample <= 1) {
                        throw exception;
                    }
                    // Some plugins ignore subsampling: fall back to a plain read, still bounded
                    // by the header pixel cap and the OOM guard.
                    image = reader.read(0, reader.getDefaultReadParam());
                } catch (OutOfMemoryError error) {
                    // Allocation failed despite the bound: fail the request, keep the JVM alive.
                    throw new ImageProcessingException("image allocation failed for " + mimeType, error);
                }
                if (image == null) {
                    throw new ImageProcessingException("undecodable " + mimeType + " payload", null);
                }
                return image;
            } catch (ImageTooLargeException exception) {
                throw exception;
            } catch (IOException | RuntimeException exception) {
                throw new ImageProcessingException("undecodable " + mimeType + " payload", exception);
            } finally {
                reader.dispose();
            }
        } catch (IOException exception) {
            throw new ImageProcessingException("undecodable " + mimeType + " payload", exception);
        }
    }

    private static BufferedImage centerSquare(BufferedImage image) {
        int side = Math.min(image.getWidth(), image.getHeight());
        int x = (image.getWidth() - side) / 2;
        int y = (image.getHeight() - side) / 2;
        return image.getSubimage(x, y, side, side);
    }

    private static BufferedImage scale(BufferedImage source, int size) {
        // JPEG has no alpha channel: flatten onto white.
        BufferedImage target = new BufferedImage(size, size, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = target.createGraphics();
        try {
            graphics.setColor(Color.WHITE);
            graphics.fillRect(0, 0, size, size);
            graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            graphics.drawImage(source, 0, 0, size, size, null);
        } finally {
            graphics.dispose();
        }
        return target;
    }

    private static byte[] encodeJpeg(BufferedImage image) throws IOException {
        ImageWriter writer = ImageIO.getImageWritersByFormatName("jpeg").next();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (ImageOutputStream imageOutput = ImageIO.createImageOutputStream(output)) {
            writer.setOutput(imageOutput);
            ImageWriteParam parameters = writer.getDefaultWriteParam();
            parameters.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
            parameters.setCompressionQuality(JPEG_QUALITY);
            writer.write(null, new IIOImage(image, null, null), parameters);
        } finally {
            writer.dispose();
        }
        return output.toByteArray();
    }

    private static String sha256Hex(byte[] bytes) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 unavailable", exception);
        }
    }
}
