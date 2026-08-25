package com.excellentcalendar.cloud.userdevice.api;

import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.platform.api.ApiFieldErrorResponse;
import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import com.excellentcalendar.cloud.userdevice.application.ProfileService;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.PreferencesSnapshot;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.ProfileSnapshot;
import com.excellentcalendar.cloud.userdevice.domain.ReminderMethod;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validator;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@RestController
@RequestMapping("/api/v1/users/me")
public class UserController {

    private final ProfileService profileService;
    private final UserResponseAssembler assembler;
    private final ObjectMapper objectMapper;
    private final Validator validator;

    public UserController(
            ProfileService profileService,
            UserResponseAssembler assembler,
            ObjectMapper objectMapper,
            Validator validator) {
        this.profileService = profileService;
        this.assembler = assembler;
        this.objectMapper = objectMapper;
        this.validator = validator;
    }

    @GetMapping
    public ApiResultResponse<CurrentUserResponseDto> getCurrent() {
        AuthenticatedPrincipal principal = requirePrincipal();
        return ApiResultResponse.success(
                assembler.assemble(principal, requireProfile(principal), requirePreferences(principal), null),
                RequestContext.requestId());
    }

    @PatchMapping
    public ApiResultResponse<CurrentUserResponseDto> updateCurrent(@RequestBody JsonNode body) {
        UpdateCurrentUserRequestDto request = bindProtocolCompliantBody(body);
        AuthenticatedPrincipal principal = requirePrincipal();
        UUID userId = principal.accountId();
        ProfileService.UpdateResult result = profileService.update(
                userId,
                new ProfileService.ProfileUpdate(request.username(), request.displayName()),
                new ProfileService.PreferencesUpdate(
                        request.locale(),
                        request.timezone(),
                        request.defaultReminderMethods() == null
                                ? null
                                : request.defaultReminderMethods().stream()
                                        .map(ReminderMethod::fromWire)
                                        .toList(),
                        request.settings()));
        return ApiResultResponse.success(
                assembler.assemble(principal, result.profile(), result.preferences(), null),
                RequestContext.requestId());
    }

    /**
     * Protocol-shape checks that plain record binding cannot express: the schema requires at
     * least one property ({@code minProperties: 1}) and has no nullable branches, so an empty
     * object or any explicit JSON null must fail with API_VALIDATION_FAILED. Bean Validation
     * constraints then run over the bound record.
     */
    private UpdateCurrentUserRequestDto bindProtocolCompliantBody(JsonNode body) {
        if (body == null || !body.isObject() || body.size() == 0) {
            throw new ApiException(ApiErrorCode.API_VALIDATION_FAILED, List.of());
        }
        List<String> explicitNulls = new ArrayList<>();
        body.properties().forEach(entry -> {
            if (entry.getValue().isNull()) {
                explicitNulls.add(entry.getKey());
            }
        });
        if (!explicitNulls.isEmpty()) {
            throw new ApiException(ApiErrorCode.API_VALIDATION_FAILED,
                    explicitNulls.stream()
                            .map(field -> new ApiFieldErrorResponse(
                                    field, ApiErrorCode.API_VALIDATION_FAILED.code(),
                                    field + " does not accept an explicit null value"))
                            .toList());
        }
        UpdateCurrentUserRequestDto request =
                objectMapper.treeToValue(body, UpdateCurrentUserRequestDto.class);
        Set<ConstraintViolation<UpdateCurrentUserRequestDto>> violations = validator.validate(request);
        if (!violations.isEmpty()) {
            throw new ApiException(ApiErrorCode.API_VALIDATION_FAILED,
                    violations.stream()
                            .map(violation -> new ApiFieldErrorResponse(
                                    violation.getPropertyPath().toString(),
                                    ApiErrorCode.API_VALIDATION_FAILED.code(),
                                    violation.getMessage()))
                            .toList());
        }
        return request;
    }

    private ProfileSnapshot requireProfile(AuthenticatedPrincipal principal) {
        return profileService.findProfile(principal.accountId()).orElseThrow();
    }

    private PreferencesSnapshot requirePreferences(AuthenticatedPrincipal principal) {
        return profileService.findPreferences(principal.accountId()).orElseThrow();
    }

    private static AuthenticatedPrincipal requirePrincipal() {
        Object value = SecurityContextHolder.getContext().getAuthentication().getPrincipal();
        if (value instanceof AuthenticatedPrincipal principal) {
            return principal;
        }
        throw new IllegalStateException("no authenticated principal");
    }
}
