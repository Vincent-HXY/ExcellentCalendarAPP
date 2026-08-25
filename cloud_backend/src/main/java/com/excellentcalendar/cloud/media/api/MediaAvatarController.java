package com.excellentcalendar.cloud.media.api;

import com.excellentcalendar.cloud.media.application.AvatarAssetService;
import java.util.Optional;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Internal avatar serving path (user-authorized, not part of the ApiResult contract): public
 * read-only bytes for active assets only, with ETag revalidation. See
 * docs/decisions/0004-identity-tech-selection.md.
 */
@RestController
@RequestMapping("/api/v1/media/avatars")
public class MediaAvatarController {

    private final AvatarAssetService assetService;

    public MediaAvatarController(AvatarAssetService assetService) {
        this.assetService = assetService;
    }

    @GetMapping("/{assetId}")
    public ResponseEntity<byte[]> main(
            @PathVariable String assetId,
            @RequestHeader(value = HttpHeaders.IF_NONE_MATCH, required = false) String ifNoneMatch) {
        return serve(parseAssetId(assetId), ifNoneMatch, false);
    }

    @GetMapping("/{assetId}/thumbnail")
    public ResponseEntity<byte[]> thumbnail(
            @PathVariable String assetId,
            @RequestHeader(value = HttpHeaders.IF_NONE_MATCH, required = false) String ifNoneMatch) {
        return serve(parseAssetId(assetId), ifNoneMatch, true);
    }

    /**
     * A non-UUID assetId can never name an asset: 404 instead of a binding failure. The internal
     * serving path is outside the ApiResult contract (ADR-0004 §6).
     */
    private static UUID parseAssetId(String assetId) {
        try {
            return UUID.fromString(assetId);
        } catch (IllegalArgumentException exception) {
            return null;
        }
    }

    private ResponseEntity<byte[]> serve(UUID assetId, String ifNoneMatch, boolean thumbnail) {
        if (assetId == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        Optional<AvatarAssetService.StoredAsset> asset = assetService.findStored(assetId);
        if (asset.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        Optional<byte[]> content = thumbnail
                ? assetService.loadThumbnail(asset.get().storageKey())
                : assetService.loadMain(asset.get().storageKey());
        if (content.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        String etag = assetService.findActive(assetId)
                .map(AvatarAssetService.AvatarAssetSnapshot::etag)
                .map(value -> "\"" + value + "\"")
                .orElse(null);
        if (etag != null && IfNoneMatch.matches(ifNoneMatch, etag)) {
            return ResponseEntity.status(HttpStatus.NOT_MODIFIED).eTag(etag).build();
        }
        ResponseEntity.BodyBuilder builder = ResponseEntity.ok()
                .contentType(org.springframework.http.MediaType.IMAGE_JPEG)
                .cacheControl(CacheControl.noCache());
        if (etag != null) {
            builder = builder.eTag(etag);
        }
        return builder.body(content.get());
    }
}
