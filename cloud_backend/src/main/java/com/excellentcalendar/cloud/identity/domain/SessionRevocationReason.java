package com.excellentcalendar.cloud.identity.domain;

public enum SessionRevocationReason {
    logout("logout"),
    logout_all("logout_all"),
    password_changed("password_changed"),
    password_reset("password_reset"),
    email_changed("email_changed"),
    refresh_token_reused("refresh_token_reused"),
    account_disabled("account_disabled"),
    expired("expired");

    private final String wireValue;

    SessionRevocationReason(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }
}
