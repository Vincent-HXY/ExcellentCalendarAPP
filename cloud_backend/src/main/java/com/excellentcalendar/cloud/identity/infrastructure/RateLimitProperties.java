package com.excellentcalendar.cloud.identity.infrastructure;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("excellent-calendar.security.rate-limit")
public class RateLimitProperties {

    private int loginMaxPerWindow = 10;
    private int loginWindowSeconds = 60;
    private int registerMaxPerWindow = 5;
    private int registerWindowSeconds = 3600;
    private int challengeMaxPerWindow = 10;
    private int challengeWindowSeconds = 60;
    private int passwordResetMaxPerWindow = 5;
    private int passwordResetWindowSeconds = 3600;

    public int getLoginMaxPerWindow() {
        return loginMaxPerWindow;
    }

    public void setLoginMaxPerWindow(int loginMaxPerWindow) {
        this.loginMaxPerWindow = loginMaxPerWindow;
    }

    public int getLoginWindowSeconds() {
        return loginWindowSeconds;
    }

    public void setLoginWindowSeconds(int loginWindowSeconds) {
        this.loginWindowSeconds = loginWindowSeconds;
    }

    public int getRegisterMaxPerWindow() {
        return registerMaxPerWindow;
    }

    public void setRegisterMaxPerWindow(int registerMaxPerWindow) {
        this.registerMaxPerWindow = registerMaxPerWindow;
    }

    public int getRegisterWindowSeconds() {
        return registerWindowSeconds;
    }

    public void setRegisterWindowSeconds(int registerWindowSeconds) {
        this.registerWindowSeconds = registerWindowSeconds;
    }

    public int getChallengeMaxPerWindow() {
        return challengeMaxPerWindow;
    }

    public void setChallengeMaxPerWindow(int challengeMaxPerWindow) {
        this.challengeMaxPerWindow = challengeMaxPerWindow;
    }

    public int getChallengeWindowSeconds() {
        return challengeWindowSeconds;
    }

    public void setChallengeWindowSeconds(int challengeWindowSeconds) {
        this.challengeWindowSeconds = challengeWindowSeconds;
    }

    public int getPasswordResetMaxPerWindow() {
        return passwordResetMaxPerWindow;
    }

    public void setPasswordResetMaxPerWindow(int passwordResetMaxPerWindow) {
        this.passwordResetMaxPerWindow = passwordResetMaxPerWindow;
    }

    public int getPasswordResetWindowSeconds() {
        return passwordResetWindowSeconds;
    }

    public void setPasswordResetWindowSeconds(int passwordResetWindowSeconds) {
        this.passwordResetWindowSeconds = passwordResetWindowSeconds;
    }
}
