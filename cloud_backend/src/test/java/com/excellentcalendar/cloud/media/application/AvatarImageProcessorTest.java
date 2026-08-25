package com.excellentcalendar.cloud.media.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.zip.CRC32;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

/**
 * EXIF orientation normalization and decompression-bomb protection of the avatar pipeline.
 */
class AvatarImageProcessorTest {

    @Test
    void readsExifOrientationFromJpegApp1() {
        byte[] jpeg = jpegBytes(40, 20);
        byte[] withExif = insertExifOrientation(jpeg, 6);

        assertThat(JpegExifOrientation.read(jpeg)).isEmpty();
        assertThat(JpegExifOrientation.read(withExif)).contains(6);
    }

    @Test
    void appliesOrientationSixAsNinetyDegreesClockwise() {
        BufferedImage portrait = new BufferedImage(40, 20, BufferedImage.TYPE_INT_RGB);

        BufferedImage rotated = JpegExifOrientation.apply(portrait, 6);

        assertThat(rotated.getWidth()).isEqualTo(20);
        assertThat(rotated.getHeight()).isEqualTo(40);
    }

    @Test
    void orientationOneReturnsTheSameRaster() {
        BufferedImage image = new BufferedImage(30, 10, BufferedImage.TYPE_INT_RGB);

        assertThat(JpegExifOrientation.apply(image, 1)).isSameAs(image);
    }

    @Test
    void exifOrientedJpegIsNormalizedBeforeTheSquareCrop() {
        byte[] plain = jpegBytes(60, 40);
        byte[] oriented = insertExifOrientation(plain, 6);

        AvatarImageProcessor.ProcessedImage processed =
                AvatarImageProcessor.process(oriented);

        assertThat(processed.width()).isEqualTo(512);
        assertThat(processed.height()).isEqualTo(512);
        assertThat(processed.main()).isNotEmpty();
        // The rotation changed the pixels: the etag must differ from the unrotated pipeline.
        assertThat(processed.etag())
                .isNotEqualTo(AvatarImageProcessor.process(plain).etag());
    }

    @Test
    void hugeDeclaredDimensionsAreRejectedBeforeAllocation() {
        byte[] bomb = pngWithDeclaredDimensions(30000, 30000);

        assertThatThrownBy(() -> AvatarImageProcessor.process(bomb))
                .isInstanceOf(AvatarImageProcessor.ImageTooLargeException.class);
    }

    @Test
    void tinyRealImagesStillProcess() {
        byte[] png = pngBytes(16, 16);

        AvatarImageProcessor.ProcessedImage processed = AvatarImageProcessor.process(png);

        assertThat(processed.main()).isNotEmpty();
        assertThat(processed.thumbnail()).isNotEmpty();
        assertThat(processed.etag()).hasSize(64);
    }

    private static byte[] jpegBytes(int width, int height) {
        try {
            BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
            Graphics2D graphics = image.createGraphics();
            graphics.setColor(Color.RED);
            graphics.fillRect(0, 0, width, height / 2);
            graphics.setColor(Color.BLUE);
            graphics.fillRect(0, height / 2, width, height - height / 2);
            graphics.dispose();
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            ImageIO.write(image, "jpeg", output);
            return output.toByteArray();
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }

    private static byte[] pngBytes(int width, int height) {
        try {
            BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
            Graphics2D graphics = image.createGraphics();
            graphics.setColor(Color.GREEN);
            graphics.fillRect(0, 0, width, height);
            graphics.dispose();
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            ImageIO.write(image, "png", output);
            return output.toByteArray();
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }

    /**
     * Inserts an APP1/Exif segment (right after SOI) declaring only the Orientation tag.
     */
    private static byte[] insertExifOrientation(byte[] jpeg, int orientation) {
        byte[] exifTiff = minimalExifOrientation(orientation);
        int payloadLength = 6 + exifTiff.length; // "Exif\0\0" + TIFF block
        int segmentLength = 2 + payloadLength;
        byte[] result = new byte[2 + 2 + segmentLength + (jpeg.length - 2)];
        result[0] = (byte) 0xFF;
        result[1] = (byte) 0xD8;
        result[2] = (byte) 0xFF;
        result[3] = (byte) 0xE1;
        result[4] = (byte) (segmentLength >> 8);
        result[5] = (byte) segmentLength;
        byte[] exif = "Exif\0\0".getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(exif, 0, result, 6, exif.length);
        System.arraycopy(exifTiff, 0, result, 6 + exif.length, exifTiff.length);
        System.arraycopy(jpeg, 2, result, 2 + 2 + segmentLength, jpeg.length - 2);
        return result;
    }

    /**
     * Little-endian TIFF header + IFD0 with a single SHORT Orientation entry.
     */
    private static byte[] minimalExifOrientation(int orientation) {
        byte[] tiff = new byte[2 + 2 + 4 + 2 + 12];
        tiff[0] = 'I';
        tiff[1] = 'I';
        tiff[2] = 0x2A; // magic 42 (little endian), byte 3 zero
        tiff[4] = 0x08; // IFD0 offset = 8 (bytes 5-7 zero)
        tiff[8] = 0x01; // one IFD0 entry (byte 9 zero)
        tiff[10] = 0x12; // tag 0x0112 (Orientation)
        tiff[11] = 0x01;
        tiff[12] = 0x03; // type SHORT (byte 13 zero)
        tiff[14] = 0x01; // count 1 (bytes 15-17 zero)
        tiff[18] = (byte) orientation; // value in the offset field (bytes 19-21 zero)
        return tiff;
    }

    /**
     * PNG with huge IHDR dimensions but no image data: the header check must reject it.
     */
    private static byte[] pngWithDeclaredDimensions(int width, int height) {
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            output.write(new byte[]{(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A});
            output.write(chunk("IHDR", ihdr(width, height)));
            output.write(chunk("IEND", new byte[0]));
            return output.toByteArray();
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }

    private static byte[] ihdr(int width, int height) {
        return new byte[]{
                (byte) (width >> 24), (byte) (width >> 16), (byte) (width >> 8), (byte) width,
                (byte) (height >> 24), (byte) (height >> 16), (byte) (height >> 8), (byte) height,
                8, 2, 0, 0, 0};
    }

    private static byte[] chunk(String type, byte[] data) {
        CRC32 crc = new CRC32();
        byte[] typeBytes = type.getBytes(StandardCharsets.US_ASCII);
        crc.update(typeBytes);
        crc.update(data);
        long checksum = crc.getValue();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        output.writeBytes(new byte[]{(byte) (data.length >> 24), (byte) (data.length >> 16),
                (byte) (data.length >> 8), (byte) data.length});
        output.writeBytes(typeBytes);
        output.writeBytes(data);
        output.writeBytes(new byte[]{(byte) (checksum >> 24), (byte) (checksum >> 16),
                (byte) (checksum >> 8), (byte) checksum});
        return output.toByteArray();
    }

    @Test
    void sniffStillIdentifiesTheThreeContractTypes() {
        assertThat(AvatarImageProcessor.sniff(jpegBytes(10, 10))).isEqualTo(Optional.of("image/jpeg"));
        assertThat(AvatarImageProcessor.sniff(pngBytes(10, 10))).isEqualTo(Optional.of("image/png"));
        assertThat(AvatarImageProcessor.sniff("not an image".getBytes(StandardCharsets.UTF_8)))
                .isEmpty();
    }

    @Test
    void webpFormatIsKnownToThePipeline() {
        // The sejda plugin registers a WebP reader; a non-WebP payload must fail cleanly instead
        // of OOM/500. Decoding an actual WebP is covered by AvatarIT.webpUploadsAreAcceptedAndProcessed.
        byte[] fakeWebp = "RIFF????WEBP not-really".getBytes(StandardCharsets.US_ASCII);
        assertThatThrownBy(() -> AvatarImageProcessor.process(fakeWebp))
                .isInstanceOf(AvatarImageProcessor.ImageProcessingException.class);
    }
}
