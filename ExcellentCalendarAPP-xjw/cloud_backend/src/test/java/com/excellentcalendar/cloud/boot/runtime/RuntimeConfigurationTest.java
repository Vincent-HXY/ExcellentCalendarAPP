package com.excellentcalendar.cloud.boot.runtime;

import static org.assertj.core.api.Assertions.assertThatIllegalStateException;
import static org.assertj.core.api.Assertions.assertThatNoException;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class RuntimeConfigurationTest {

    @Test
    void apiAndLocalIsAValidDevelopmentCombination() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("api", "local");

        assertThatNoException().isThrownBy(
                () -> RuntimeConfiguration.validateSelectedProfile(RuntimeRole.API, environment));
    }

    @Test
    void defaultApiProfileIsValid() {
        MockEnvironment environment = new MockEnvironment();
        environment.setDefaultProfiles("api");

        assertThatNoException().isThrownBy(
                () -> RuntimeConfiguration.validateSelectedProfile(RuntimeRole.API, environment));
    }

    @Test
    void localProfileCannotRunWithoutAProcessRole() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("local");

        assertThatIllegalStateException().isThrownBy(
                () -> RuntimeConfiguration.validateSelectedProfile(RuntimeRole.API, environment));
    }

    @Test
    void multipleProcessRolesAreRejected() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("api", "worker");

        assertThatIllegalStateException().isThrownBy(
                () -> RuntimeConfiguration.validateSelectedProfile(RuntimeRole.API, environment));
    }

    @Test
    void configuredRoleMustMatchItsProfile() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("api");

        assertThatIllegalStateException().isThrownBy(
                () -> RuntimeConfiguration.validateSelectedProfile(RuntimeRole.WORKER, environment));
    }
}
