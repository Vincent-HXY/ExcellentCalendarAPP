package com.excellentcalendar.cloud.media.application;

import java.awt.geom.AffineTransform;
import java.awt.image.AffineTransformOp;
import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Optional;

/**
 * Minimal JPEG EXIF orientation reader and raster normalizer. ImageIO ignores the EXIF
 * Orientation tag, so portrait phone photos (orientation 6/8) would otherwise be cropped and
 * stored sideways. The APP1/Exif TIFF walk is bounded by the buffer and only reads tag 0x0112.
 */
final class JpegExifOrientation {

    private static final int TAG_ORIENTATION = 0x0112;
    private static final int TIFF_TYPE_SHORT = 3;
    private static final int TIFF_MAGIC = 0x002A;

    private JpegExifOrientation() {
    }

    /**
     * Returns the EXIF Orientation value (1-8) declared by the JPEG, if present and valid.
     */
    static Optional<Integer> read(byte[] bytes) {
        if (bytes.length < 4 || (bytes[0] & 0xFF) != 0xFF || (bytes[1] & 0xFF) != 0xD8) {
            return Optional.empty();
        }
        int position = 2;
        while (position + 4 <= bytes.length) {
            if ((bytes[position] & 0xFF) != 0xFF) {
                return Optional.empty();
            }
            int marker;
            do {
                marker = bytes[position++] & 0xFF;
            } while (marker == 0xFF && position < bytes.length);
            if (marker == 0xD9 || marker == 0xDA) {
                // EOI or SOS (SOS has no length field).
                return Optional.empty();
            }
            if (position + 2 > bytes.length) {
                return Optional.empty();
            }
            int length = ((bytes[position] & 0xFF) << 8) | (bytes[position + 1] & 0xFF);
            if (length < 2 || position + length > bytes.length) {
                return Optional.empty();
            }
            if (marker == 0xE1 && length >= 8) {
                // APP1 payload starts at position+2; skip the 6-byte "Exif\0\0" header to the TIFF.
                Optional<Integer> orientation =
                        parseExif(bytes, position + 2 + 6, position + 2 + length);
                if (orientation.isPresent()) {
                    return orientation;
                }
            }
            position += length;
        }
        return Optional.empty();
    }

    /**
     * Applies the EXIF orientation transform (1-8) to the decoded raster.
     */
    static BufferedImage apply(BufferedImage image, int orientation) {
        AffineTransform transform = switch (orientation) {
            case 1 -> null;
            case 2 -> new AffineTransform(-1, 0, 0, 1, image.getWidth() - 1.0, 0);
            case 3 -> new AffineTransform(-1, 0, 0, -1, image.getWidth() - 1.0, image.getHeight() - 1.0);
            case 4 -> new AffineTransform(1, 0, 0, -1, 0, image.getHeight() - 1.0);
            case 5 -> new AffineTransform(0, 1, 1, 0, 0, 0);
            case 6 -> new AffineTransform(0, 1, -1, 0, image.getHeight() - 1.0, 0);
            case 7 -> new AffineTransform(0, -1, -1, 0, image.getHeight() - 1.0, image.getWidth() - 1.0);
            case 8 -> new AffineTransform(0, -1, 1, 0, 0, image.getWidth() - 1.0);
            default -> throw new IllegalArgumentException("unknown EXIF orientation: " + orientation);
        };
        if (transform == null) {
            return image;
        }
        boolean swapsAxes = orientation >= 5;
        int targetWidth = swapsAxes ? image.getHeight() : image.getWidth();
        int targetHeight = swapsAxes ? image.getWidth() : image.getHeight();
        BufferedImage source = image;
        int sourceType = image.getType();
        if (sourceType == BufferedImage.TYPE_BYTE_INDEXED || sourceType == BufferedImage.TYPE_CUSTOM) {
            // BICUBIC cannot filter indexed rasters; EXIF is JPEG-only anyway, keep this defensive.
            source = new BufferedImage(image.getWidth(), image.getHeight(), BufferedImage.TYPE_INT_RGB);
            source.getGraphics().drawImage(image, 0, 0, null);
            sourceType = BufferedImage.TYPE_INT_RGB;
        }
        AffineTransformOp operation = new AffineTransformOp(transform, AffineTransformOp.TYPE_BICUBIC);
        return operation.filter(source, new BufferedImage(targetWidth, targetHeight, sourceType));
    }

    private static Optional<Integer> parseExif(byte[] bytes, int tiffOffset, int tiffEnd) {
        if (tiffOffset + 8 > tiffEnd || tiffOffset + 8 > bytes.length) {
            return Optional.empty();
        }
        ByteOrder order;
        if (bytes[tiffOffset] == 'I' && bytes[tiffOffset + 1] == 'I') {
            order = ByteOrder.LITTLE_ENDIAN;
        } else if (bytes[tiffOffset] == 'M' && bytes[tiffOffset + 1] == 'M') {
            order = ByteOrder.BIG_ENDIAN;
        } else {
            return Optional.empty();
        }
        ByteBuffer buffer = ByteBuffer.wrap(bytes).order(order);
        if ((buffer.getShort(tiffOffset + 2) & 0xFFFF) != TIFF_MAGIC) {
            return Optional.empty();
        }
        int entryList = tiffOffset + buffer.getInt(tiffOffset + 4);
        if (entryList + 2 > tiffEnd || entryList + 2 > bytes.length) {
            return Optional.empty();
        }
        int count = buffer.getShort(entryList) & 0xFFFF;
        for (int index = 0; index < count; index++) {
            int entry = entryList + 2 + index * 12;
            if (entry + 12 > tiffEnd || entry + 12 > bytes.length) {
                return Optional.empty();
            }
            int tag = buffer.getShort(entry) & 0xFFFF;
            int type = buffer.getShort(entry + 2) & 0xFFFF;
            int components = buffer.getInt(entry + 4);
            if (tag == TAG_ORIENTATION && type == TIFF_TYPE_SHORT && components == 1) {
                int value = buffer.getShort(entry + 8) & 0xFFFF;
                if (value >= 1 && value <= 8) {
                    return Optional.of(value);
                }
            }
        }
        return Optional.empty();
    }
}
