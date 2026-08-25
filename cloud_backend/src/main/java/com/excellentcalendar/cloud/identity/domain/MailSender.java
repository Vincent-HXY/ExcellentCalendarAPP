package com.excellentcalendar.cloud.identity.domain;

/**
 * Port for outbound mail. The dev/local implementation logs the verification code to the console
 * as the integration inbox; no real SMTP is wired in this phase.
 */
public interface MailSender {

    void sendVerificationCode(String to, EmailActionPurpose purpose, String code);
}
