package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

class AvatarIT extends ApiIntegrationTestSupport {

    @BeforeEach
    void clearMail() {
        mailSender.clear();
    }

    private String registerVerifyAndLogin() {
        String email = "user-" + UUID.randomUUID() + "@example.com";
        ApiResponse register = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)),
                "Idempotency-Key", UUID.randomUUID().toString());
        String challengeId = register.body().path("data").path("challenge").path("challenge_id").asText();
        postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)));
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        return login.body().path("data").path("tokens").path("access_token").asText();
    }

    private ApiResponse upload(String access, byte[] bytes, String declaredType, String key) {
        return postMultipart("/users/me/avatar", Map.of("file", bytes), Map.of("file", declaredType),
                "Authorization", auth(access), "Idempotency-Key", key);
    }

    @Test
    void uploadServesAndDeletesAvatarWithEtagSemantics() {
        String access = registerVerifyAndLogin();
        byte[] png = pngBytes(300, 200, Color.RED);

        ApiResponse uploaded = upload(access, png, "image/png", UUID.randomUUID().toString());
        assertThat(uploaded.status()).isEqualTo(HttpStatus.OK.value());
        JsonNode avatar = uploaded.body().path("data").path("profile").path("avatar");
        assertThat(avatar.path("asset_id").asText()).isNotBlank();
        assertThat(avatar.path("url").asText()).endsWith("/api/v1/media/avatars/" + avatar.path("asset_id").asText());
        assertThat(avatar.path("thumbnail_url").asText())
                .endsWith("/api/v1/media/avatars/" + avatar.path("asset_id").asText() + "/thumbnail");
        assertThat(avatar.path("etag").asText()).hasSize(64);
        assertThat(avatar.path("updated_at").asText()).endsWith("Z");
        String assetId = avatar.path("asset_id").asText();
        String etag = avatar.path("etag").asText();

        // Public serving works and honours ETag revalidation.
        RawResponse main = getRaw("/media/avatars/" + assetId);
        assertThat(main.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(main.body()).isNotEmpty();
        assertThat(main.headers().get("etag").get(0)).isEqualTo("\"" + etag + "\"");

        RawResponse notModified = getRaw("/media/avatars/" + assetId, "If-None-Match", "\"" + etag + "\"");
        assertThat(notModified.status()).isEqualTo(HttpStatus.NOT_MODIFIED.value());

        RawResponse thumbnail = getRaw("/media/avatars/" + assetId + "/thumbnail");
        assertThat(thumbnail.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(thumbnail.body()).isNotEmpty();

        // get_current includes the same avatar info.
        ApiResponse me = getJson("/users/me", "Authorization", auth(access));
        assertThat(me.body().path("data").path("profile").path("avatar").path("asset_id").asText())
                .isEqualTo(assetId);

        // Delete restores the client default-avatar semantics and stops serving bytes.
        ApiResponse deleted = deleteJson("/users/me/avatar", "Authorization", auth(access));
        assertThat(deleted.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(deleted.body().path("data").path("profile").path("avatar").isNull()).isTrue();
        assertThat(getRaw("/media/avatars/" + assetId).status()).isEqualTo(HttpStatus.NOT_FOUND.value());

        // Delete is naturally idempotent.
        assertThat(deleteJson("/users/me/avatar", "Authorization", auth(access)).status())
                .isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void replacingAnAvatarSoftDeletesTheOldAssetButKeepsTheOldOnFailure() {
        String access = registerVerifyAndLogin();
        ApiResponse first = upload(access, pngBytes(200, 200, Color.BLUE), "image/png",
                UUID.randomUUID().toString());
        String firstAsset = first.body().path("data").path("profile").path("avatar").path("asset_id").asText();

        // Failed upload (unsupported type) must preserve the old avatar.
        ApiResponse failed = upload(access, "not-an-image".getBytes(StandardCharsets.UTF_8),
                "image/png", UUID.randomUUID().toString());
        assertThat(failed.status()).isEqualTo(HttpStatus.UNSUPPORTED_MEDIA_TYPE.value());
        assertThat(failed.body().path("error").path("code").asText()).isEqualTo("AVATAR_TYPE_UNSUPPORTED");
        ApiResponse me = getJson("/users/me", "Authorization", auth(access));
        assertThat(me.body().path("data").path("profile").path("avatar").path("asset_id").asText())
                .isEqualTo(firstAsset);

        // Successful replacement soft-deletes the old asset.
        ApiResponse second = upload(access, pngBytes(200, 200, Color.GREEN), "image/png",
                UUID.randomUUID().toString());
        String secondAsset = second.body().path("data").path("profile").path("avatar").path("asset_id").asText();
        assertThat(secondAsset).isNotEqualTo(firstAsset);
        assertThat(getRaw("/media/avatars/" + firstAsset).status()).isEqualTo(HttpStatus.NOT_FOUND.value());
        assertThat(getRaw("/media/avatars/" + secondAsset).status()).isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void oversizedAndMisdeclaredUploadsAreRejectedByActualContent() {
        String access = registerVerifyAndLogin();

        ApiResponse oversized = upload(access, new byte[5 * 1024 * 1024 + 1], "image/png",
                UUID.randomUUID().toString());
        assertThat(oversized.status()).isEqualTo(HttpStatus.PAYLOAD_TOO_LARGE.value());
        assertThat(oversized.body().path("error").path("code").asText()).isEqualTo("AVATAR_TOO_LARGE");

        // Actual content wins over the declared Content-Type.
        ApiResponse misdeclared = upload(access, pngBytes(100, 100, Color.RED), "image/gif",
                UUID.randomUUID().toString());
        assertThat(misdeclared.status()).isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void imagesBetweenOneAndFiveMiBAreAccepted() {
        // Regression for the parser ceiling: Boot's 1 MB multipart default must not reject
        // contract-valid avatars in (1 MiB, 5 MiB] before the processor's exact check runs.
        String access = registerVerifyAndLogin();
        byte[] largePng = noiseImageBytes(1024, 1024, 42);
        assertThat(largePng.length).isGreaterThan(1024 * 1024).isLessThanOrEqualTo(5 * 1024 * 1024);

        ApiResponse uploaded = upload(access, largePng, "image/png", UUID.randomUUID().toString());
        assertThat(uploaded.status()).as("large upload body: %s", uploaded.body())
                .isEqualTo(HttpStatus.OK.value());
        String assetId = uploaded.body().path("data").path("profile").path("avatar").path("asset_id").asText();
        assertThat(getRaw("/media/avatars/" + assetId).status()).isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void uploadIsIdempotentPerKey() {
        String access = registerVerifyAndLogin();
        String key = UUID.randomUUID().toString();
        byte[] png = pngBytes(120, 120, Color.YELLOW);

        ApiResponse first = upload(access, png, "image/png", key);
        ApiResponse second = upload(access, png, "image/png", key);
        assertThat(first.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.body().path("data").path("profile").path("avatar").path("asset_id").asText())
                .isEqualTo(first.body().path("data").path("profile").path("avatar").path("asset_id").asText());
    }

    @Test
    void webpUploadsAreAcceptedAndProcessed() {
        String access = registerVerifyAndLogin();
        byte[] webp = imageBytes(120, 120, Color.ORANGE, "webp");

        ApiResponse uploaded = upload(access, webp, "image/webp", UUID.randomUUID().toString());
        assertThat(uploaded.status()).as("webp upload body: %s", uploaded.body())
                .isEqualTo(HttpStatus.OK.value());
        String assetId = uploaded.body().path("data").path("profile").path("avatar").path("asset_id").asText();
        // Processed to square JPEG and served with the etag-based caching semantics.
        RawResponse main = getRaw("/media/avatars/" + assetId);
        assertThat(main.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(main.body()).isNotEmpty();
    }

    @Test
    void uploadRequiresAuthenticationAndTheFilePart() {
        ApiResponse unauthenticated = postMultipart(
                "/users/me/avatar", Map.of("file", pngBytes(10, 10, Color.BLACK)),
                Map.of("file", "image/png"), "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(unauthenticated.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(unauthenticated.body().path("error").path("code").asText())
                .isEqualTo("API_UNAUTHENTICATED");

        String access = registerVerifyAndLogin();
        ApiResponse noPart = postMultipart("/users/me/avatar", Map.of(), Map.of(),
                "Authorization", auth(access), "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(noPart.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(noPart.body().path("error").path("code").asText()).isEqualTo("API_VALIDATION_FAILED");
    }

    @Test
    void nonUuidAssetIdIsA404AndIfNoneMatchFollowsRfcSemantics() {
        // A non-UUID assetId can never name an asset: 404, not a 500 binding failure.
        assertThat(getRaw("/media/avatars/not-a-uuid").status()).isEqualTo(HttpStatus.NOT_FOUND.value());

        String access = registerVerifyAndLogin();
        ApiResponse uploaded = upload(access, pngBytes(120, 120, Color.RED), "image/png",
                UUID.randomUUID().toString());
        String assetId = uploaded.body().path("data").path("profile").path("avatar").path("asset_id").asText();
        String etag = uploaded.body().path("data").path("profile").path("avatar").path("etag").asText();

        // RFC 9110: a list matches when ANY element matches.
        assertThat(getRaw("/media/avatars/" + assetId,
                "If-None-Match", "\"other\", \"" + etag + "\"").status())
                .isEqualTo(HttpStatus.NOT_MODIFIED.value());
        assertThat(getRaw("/media/avatars/" + assetId, "If-None-Match", "*").status())
                .isEqualTo(HttpStatus.NOT_MODIFIED.value());
        assertThat(getRaw("/media/avatars/" + assetId, "If-None-Match", "W/\"" + etag + "\"").status())
                .isEqualTo(HttpStatus.NOT_MODIFIED.value());
        // No match, and a substring coincidence must NOT match.
        assertThat(getRaw("/media/avatars/" + assetId, "If-None-Match", "\"other\"").status())
                .isEqualTo(HttpStatus.OK.value());
        assertThat(getRaw("/media/avatars/" + assetId, "If-None-Match", "\"" + etag + "12\"").status())
                .isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void decompressionBombIsRejectedAsTooLargeWithoutDecoding() {
        String access = registerVerifyAndLogin();
        byte[] bomb = pngWithDeclaredDimensions(30000, 30000);

        ApiResponse uploaded = upload(access, bomb, "image/png", UUID.randomUUID().toString());
        assertThat(uploaded.status()).isEqualTo(HttpStatus.PAYLOAD_TOO_LARGE.value());
        assertThat(uploaded.body().path("error").path("code").asText()).isEqualTo("AVATAR_TOO_LARGE");
    }

    private static byte[] pngBytes(int width, int height, Color color) {
        return imageBytes(width, height, color, "png");
    }

    /**
     * PNG with huge IHDR dimensions but no image data: a decompression bomb for the header check.
     */
    private static byte[] pngWithDeclaredDimensions(int width, int height) {
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            output.write(new byte[]{(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A});
            byte[] ihdr = new byte[]{
                    (byte) (width >> 24), (byte) (width >> 16), (byte) (width >> 8), (byte) width,
                    (byte) (height >> 24), (byte) (height >> 16), (byte) (height >> 8), (byte) height,
                    8, 2, 0, 0, 0};
            output.write(pngChunk("IHDR", ihdr));
            output.write(pngChunk("IEND", new byte[0]));
            return output.toByteArray();
        } catch (Exception exception) {
            throw new IllegalStateException("cannot encode bomb png", exception);
        }
    }

    private static byte[] pngChunk(String type, byte[] data) {
        java.util.zip.CRC32 crc = new java.util.zip.CRC32();
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

    /**
     * Deterministic incompressible noise image so the encoded PNG reliably lands above 1 MiB.
     */
    private static byte[] noiseImageBytes(int width, int height, long seed) {
        java.util.Random random = new java.util.Random(seed);
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                image.setRGB(x, y, random.nextInt(0x1000000));
            }
        }
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            ImageIO.write(image, "png", output);
            return output.toByteArray();
        } catch (Exception exception) {
            throw new IllegalStateException("cannot encode noise png", exception);
        }
    }

    private static byte[] imageBytes(int width, int height, Color color, String format) {
        try {
            BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
            Graphics2D graphics = image.createGraphics();
            graphics.setColor(color);
            graphics.fillRect(0, 0, width, height);
            graphics.dispose();
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            ImageIO.write(image, format, output);
            return output.toByteArray();
        } catch (Exception exception) {
            throw new IllegalStateException("cannot encode " + format, exception);
        }
    }
}
