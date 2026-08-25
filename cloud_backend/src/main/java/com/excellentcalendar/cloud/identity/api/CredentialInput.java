package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.domain.VerificationCredentialType;
import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;

/**
 * Normalizes the {@code oneOf} credential schema: {@code code} requires the 6-digit code,
 * {@code link_token} requires the opaque token. Link tokens are not issued in this phase, so the
 * service maps them to AUTH_VERIFICATION_INVALID.
 */
public record CredentialInput(VerificationCredentialType type, String code) {

    public static CredentialInput of(VerificationCredentialDto dto) {
        if ("code".equals(dto.credentialType())) {
            if (dto.code() == null) {
                throw new ApiException(ApiErrorCode.API_VALIDATION_FAILED);
            }
            return new CredentialInput(VerificationCredentialType.CODE, dto.code());
        }
        if (dto.linkToken() == null) {
            throw new ApiException(ApiErrorCode.API_VALIDATION_FAILED);
        }
        return new CredentialInput(VerificationCredentialType.LINK_TOKEN, null);
    }
}
