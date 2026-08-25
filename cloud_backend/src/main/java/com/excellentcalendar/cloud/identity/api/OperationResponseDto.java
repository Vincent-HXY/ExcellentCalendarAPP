package com.excellentcalendar.cloud.identity.api;

public record OperationResponseDto(boolean performed, String message) {

    public static OperationResponseDto done() {
        return new OperationResponseDto(true, null);
    }

    public static OperationResponseDto of(boolean performed) {
        return new OperationResponseDto(performed, null);
    }
}
