package com.excellentcalendar.cloud.identity.domain;

public enum UserAccountStatus {
    pending_verification("pending_verification"),
    active("active"),
    disabled("disabled"),
    deleted("deleted");

    private final String wireValue;

    UserAccountStatus(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }

    public static UserAccountStatus fromWire(String wireValue) {
        for (UserAccountStatus status : values()) {
            if (status.wireValue.equals(wireValue)) {
                return status;
            }
        }
        throw new IllegalArgumentException("unknown account status: " + wireValue);
    }
}
