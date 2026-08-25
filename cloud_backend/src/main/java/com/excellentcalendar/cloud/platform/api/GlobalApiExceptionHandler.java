package com.excellentcalendar.cloud.platform.api;

import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.ConstraintViolationException;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.resource.NoResourceFoundException;
import org.springframework.http.converter.HttpMessageNotReadableException;

/**
 * Maps every declared failure branch to the ApiResult envelope. Unknown failures become
 * API_INTERNAL_ERROR with the full exception logged server-side (never in the response).
 */
@RestControllerAdvice
public class GlobalApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalApiExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleApiException(
            ApiException exception, HttpServletResponse response) {
        ApiErrorResponse error = exception.toErrorResponse();
        HttpHeaders headers = new HttpHeaders();
        if (exception.code() == ApiErrorCode.API_RATE_LIMITED && exception.retryAfterSeconds() != null) {
            headers.set(HttpHeaders.RETRY_AFTER, String.valueOf(exception.retryAfterSeconds()));
        }
        return ResponseEntity.status(exception.code().httpStatus())
                .headers(headers)
                .body(ApiResultResponse.failure(error, RequestContext.requestId()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleBeanValidation(MethodArgumentNotValidException exception) {
        List<ApiFieldErrorResponse> fieldErrors = exception.getBindingResult().getFieldErrors().stream()
                .map(this::toFieldError)
                .toList();
        return ResponseEntity.status(ApiErrorCode.API_VALIDATION_FAILED.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_VALIDATION_FAILED, fieldErrors),
                        RequestContext.requestId()));
    }

    @ExceptionHandler(HandlerMethodValidationException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleMethodValidation(HandlerMethodValidationException exception) {
        List<ApiFieldErrorResponse> fieldErrors = exception.getAllErrors().stream()
                .filter(FieldError.class::isInstance)
                .map(FieldError.class::cast)
                .map(this::toFieldError)
                .toList();
        return ResponseEntity.status(ApiErrorCode.API_VALIDATION_FAILED.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_VALIDATION_FAILED, fieldErrors),
                        RequestContext.requestId()));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleConstraintViolation(ConstraintViolationException exception) {
        return ResponseEntity.status(ApiErrorCode.API_VALIDATION_FAILED.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_VALIDATION_FAILED),
                        RequestContext.requestId()));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleUnreadableBody(HttpMessageNotReadableException exception) {
        return ResponseEntity.status(ApiErrorCode.API_VALIDATION_FAILED.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_VALIDATION_FAILED),
                        RequestContext.requestId()));
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleUploadTooLarge(
            MaxUploadSizeExceededException exception, jakarta.servlet.http.HttpServletRequest request) {
        // AVATAR_TOO_LARGE is the avatar endpoint's declared code; other future multipart
        // endpoints must not silently inherit it.
        ApiErrorCode code = request.getRequestURI().endsWith("/api/v1/users/me/avatar")
                ? ApiErrorCode.AVATAR_TOO_LARGE
                : ApiErrorCode.API_VALIDATION_FAILED;
        return ResponseEntity.status(code.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(code),
                        RequestContext.requestId()));
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleUnsupportedMediaType(
            HttpMediaTypeNotSupportedException exception) {
        return ResponseEntity.status(ApiErrorCode.API_VALIDATION_FAILED.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_VALIDATION_FAILED),
                        RequestContext.requestId()));
    }

    @ExceptionHandler(org.springframework.web.multipart.support.MissingServletRequestPartException.class)
    public ResponseEntity<ApiResultResponse<Void>> handleMissingPart(
            org.springframework.web.multipart.support.MissingServletRequestPartException exception) {
        return ResponseEntity.status(ApiErrorCode.API_VALIDATION_FAILED.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_VALIDATION_FAILED,
                                List.of(new ApiFieldErrorResponse(
                                        exception.getRequestPartName(),
                                        ApiErrorCode.API_VALIDATION_FAILED.code(),
                                        "required multipart part is missing"))),
                        RequestContext.requestId()));
    }

    @ExceptionHandler({NoResourceFoundException.class, NoHandlerFoundException.class})
    public ResponseEntity<Void> handleNotFound(Exception exception) throws Exception {
        throw exception;
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<Void> handleMethodNotAllowed(HttpRequestMethodNotSupportedException exception)
            throws Exception {
        throw exception;
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResultResponse<Void>> handleUnexpected(Exception exception) {
        log.error("Unhandled request failure [request_id:{}]", RequestContext.requestId(), exception);
        return ResponseEntity.status(ApiErrorCode.API_INTERNAL_ERROR.httpStatus())
                .body(ApiResultResponse.failure(
                        ApiErrorResponse.of(ApiErrorCode.API_INTERNAL_ERROR),
                        RequestContext.requestId()));
    }

    private ApiFieldErrorResponse toFieldError(FieldError error) {
        return new ApiFieldErrorResponse(
                error.getField(),
                ApiErrorCode.API_VALIDATION_FAILED.code(),
                error.getDefaultMessage() == null ? "Invalid value" : error.getDefaultMessage());
    }
}
