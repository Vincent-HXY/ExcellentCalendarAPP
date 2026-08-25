package com.excellentcalendar.cloud.identity.domain;

public enum EmailActionPurpose {
    registration_verification("registration_verification"),
    email_change("email_change"),
    password_reset("password_reset");

    private final String wireValue;

    EmailActionPurpose(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }
}
