package com.excellentcalendar.cloud.identity.domain;

public enum EmailChangeStatus {
    pending("pending"),
    verified("verified"),
    expired("expired"),
    cancelled("cancelled");

    private final String wireValue;

    EmailChangeStatus(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }
}
