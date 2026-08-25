package com.excellentcalendar.cloud.identity.application.support;

import com.excellentcalendar.cloud.identity.domain.PasswordHasher;
import org.springframework.stereotype.Component;

/**
 * Equalizes the cost of authentication paths that find no account (unknown email on login and on
 * password-reset request) by burning one Argon2 match against a valid dummy hash, so response
 * timing does not reveal whether an email is registered. Same Argon2 parameters as the real
 * hasher (ADR-0004 §4).
 */
@Component
public class TimingEqualizer {

    private final PasswordHasher passwordHasher;
    private final String dummyHash;

    public TimingEqualizer(PasswordHasher passwordHasher) {
        this.passwordHasher = passwordHasher;
        this.dummyHash = new org.springframework.security.crypto.argon2.Argon2PasswordEncoder(
                16, 32, 1, 65536, 3)
                .encode("dummy-timing-equalizer");
    }

    public void burn(String input) {
        passwordHasher.matches(input, dummyHash);
    }
}
