package com.excellentcalendar.cloud.boot.runtime;

import jakarta.validation.constraints.NotNull;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties("excellent-calendar.runtime")
public class RuntimeProperties {

    @NotNull
    private RuntimeRole role = RuntimeRole.API;

    public RuntimeRole getRole() {
        return role;
    }

    public void setRole(RuntimeRole role) {
        this.role = role;
    }
}
