package com.excellentcalendar.cloud.platform.idempotency;

import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiErrorResponse;
import com.excellentcalendar.cloud.platform.api.ApiFieldErrorResponse;
import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.ApiResultWriter;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import tools.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

/**
 * Idempotency-Key guard for the endpoints whose contract requires it. A claimed key replays the
 * stored success response byte-for-byte; a failed business execution releases the key so the
 * client can retry with the same key.
 */
public class IdempotencyFilter extends OncePerRequestFilter {

    public static final String HEADER = "Idempotency-Key";
    private static final int MAX_KEY_LENGTH = 128;
    private static final int MAX_POLL_ATTEMPTS = 100;
    private static final long POLL_INTERVAL_MILLIS = 30;

    private static final Map<String, String> SCOPES = Map.of(
            "/api/v1/auth/register", "auth.register",
            "/api/v1/auth/registration/resend", "auth.registration.resend",
            "/api/v1/auth/password-reset/request", "auth.password_reset.request",
            "/api/v1/auth/email-change/request", "auth.email_change.request",
            "/api/v1/users/me/avatar", "user.avatar.upload");

    private final IdempotencyStore store;
    private final ObjectMapper objectMapper;

    public IdempotencyFilter(IdempotencyStore store, ObjectMapper objectMapper) {
        this.store = store;
        this.objectMapper = objectMapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !"POST".equals(request.getMethod()) || !SCOPES.containsKey(request.getRequestURI());
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String key = request.getHeader(HEADER);
        if (key == null || key.isBlank() || key.length() > MAX_KEY_LENGTH) {
            ApiFieldErrorResponse fieldError = new ApiFieldErrorResponse(
                    "Idempotency-Key",
                    ApiErrorCode.API_VALIDATION_FAILED.code(),
                    "Idempotency-Key header is required");
            ApiResultResponse<Void> envelope = ApiResultResponse.failure(
                    ApiErrorResponse.of(ApiErrorCode.API_VALIDATION_FAILED, List.of(fieldError)),
                    RequestContext.requestId());
            ApiResultWriter.write(response, objectMapper, ApiErrorCode.API_VALIDATION_FAILED.httpStatus(), envelope);
            return;
        }

        String scope = SCOPES.get(request.getRequestURI()) + ":" + currentScopeUser();
        String keyHash = sha256Hex(key);

        if (!store.tryClaim(scope, keyHash)) {
            Outcome outcome = awaitStoredOrClaim(scope, keyHash);
            if (outcome instanceof Outcome.Stored stored) {
                writeStored(response, stored.response());
                return;
            }
            if (outcome instanceof Outcome.TimedOut) {
                ApiResultResponse<Void> envelope = ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_INTERNAL_ERROR),
                        RequestContext.requestId());
                ApiResultWriter.write(
                        response, objectMapper, ApiErrorCode.API_INTERNAL_ERROR.httpStatus(), envelope);
                return;
            }
            // Claimed: the previous owner released a failed execution; this request now owns the key.
        }

        ContentCachingResponseWrapper wrappedResponse = new ContentCachingResponseWrapper(response);
        filterChain.doFilter(request, wrappedResponse);
        int status = wrappedResponse.getStatus();
        if (status >= 200 && status < 300) {
            store.complete(scope, keyHash, status, wrappedResponse.getContentAsByteArray());
        } else {
            store.release(scope, keyHash);
        }
        wrappedResponse.copyBodyToResponse();
    }

    private sealed interface Outcome permits Outcome.Stored, Outcome.Claimed, Outcome.TimedOut {

        record Stored(IdempotencyStore.StoredResponse response) implements Outcome {
        }

        record Claimed() implements Outcome {
        }

        record TimedOut() implements Outcome {
        }
    }

    private Outcome awaitStoredOrClaim(String scope, String keyHash) {
        for (int attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
            Optional<IdempotencyStore.StoredResponse> stored = store.findStored(scope, keyHash);
            if (stored.isPresent()) {
                return new Outcome.Stored(stored.get());
            }
            if (store.tryClaim(scope, keyHash)) {
                return new Outcome.Claimed();
            }
            try {
                Thread.sleep(POLL_INTERVAL_MILLIS);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                return new Outcome.TimedOut();
            }
        }
        return new Outcome.TimedOut();
    }

    private void writeStored(HttpServletResponse response, IdempotencyStore.StoredResponse stored)
            throws IOException {
        response.setStatus(stored.status());
        response.setContentType("application/json");
        response.getOutputStream().write(stored.body());
    }

    private String currentScopeUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.getPrincipal() instanceof AuthenticatedPrincipal principal) {
            return principal.accountId().toString();
        }
        return "anonymous";
    }

    private static String sha256Hex(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 unavailable", exception);
        }
    }
}
