package com.excellentcalendar.cloud.identity.infrastructure;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Optional SMTP configuration under {@code excellent-calendar.mail}. The SMTP adapter only
 * activates when {@code host} is non-blank, so every value below is provider-agnostic and the
 * defaults are only meaningful once the host is set. Secrets must be injected from the
 * environment and never committed to the repository.
 */
@ConfigurationProperties("excellent-calendar.mail")
public class MailSendingProperties {

    /** SMTP host; blank disables the SMTP adapter and keeps the profile fallback. */
    private String host;

    /** SMTP port; 465 for implicit SSL, 587 for STARTTLS. */
    private int port = 587;

    /** SMTP login (usually the mailbox address). */
    private String username;

    /** SMTP password or provider authorization code (授权码). */
    private String password;

    /** From address; falls back to {@link #username} when blank. */
    private String from;

    /** Enable STARTTLS on plaintext connections (ignored when {@link #ssl} is true). */
    private boolean startTls = true;

    /** Use implicit TLS (SMTPS), typically port 465. */
    private boolean ssl;

    private int connectionTimeoutMs = 10_000;
    private int timeoutMs = 10_000;
    private int writeTimeoutMs = 10_000;

    public String getHost() {
        return host;
    }

    public void setHost(String host) {
        this.host = host;
    }

    public int getPort() {
        return port;
    }

    public void setPort(int port) {
        this.port = port;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getFrom() {
        return from;
    }

    public void setFrom(String from) {
        this.from = from;
    }

    public boolean isStartTls() {
        return startTls;
    }

    public void setStartTls(boolean startTls) {
        this.startTls = startTls;
    }

    public boolean isSsl() {
        return ssl;
    }

    public void setSsl(boolean ssl) {
        this.ssl = ssl;
    }

    public int getConnectionTimeoutMs() {
        return connectionTimeoutMs;
    }

    public void setConnectionTimeoutMs(int connectionTimeoutMs) {
        this.connectionTimeoutMs = connectionTimeoutMs;
    }

    public int getTimeoutMs() {
        return timeoutMs;
    }

    public void setTimeoutMs(int timeoutMs) {
        this.timeoutMs = timeoutMs;
    }

    public int getWriteTimeoutMs() {
        return writeTimeoutMs;
    }

    public void setWriteTimeoutMs(int writeTimeoutMs) {
        this.writeTimeoutMs = writeTimeoutMs;
    }
}
