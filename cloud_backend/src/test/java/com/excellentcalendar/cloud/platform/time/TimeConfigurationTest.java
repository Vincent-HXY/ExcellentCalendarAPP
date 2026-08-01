package com.excellentcalendar.cloud.platform.time;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

class TimeConfigurationTest {

    @Test
    void applicationClockUsesUtc() {
        assertThat(new TimeConfiguration().applicationClock().getZone()).isEqualTo(ZoneOffset.UTC);
    }
}
