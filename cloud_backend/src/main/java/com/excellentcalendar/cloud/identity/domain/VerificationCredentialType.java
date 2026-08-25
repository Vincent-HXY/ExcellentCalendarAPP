package com.excellentcalendar.cloud.identity.domain;

public enum VerificationCredentialType {
    CODE("code"),
    LINK_TOKEN("link_token");

    private final String wireValue;

    VerificationCredentialType(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }
}
