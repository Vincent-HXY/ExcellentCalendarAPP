package com.excellentcalendar.cloud.media.infrastructure;

import java.nio.file.Path;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("excellent-calendar.media.avatar")
public class MediaProperties {

    private String baseUrl = "http://localhost:8080";
    private Path dir = Path.of("./data/avatars");

    public String getBaseUrl() {
        return baseUrl;
    }

    public void setBaseUrl(String baseUrl) {
        this.baseUrl = baseUrl;
    }

    public Path getDir() {
        return dir;
    }

    public void setDir(Path dir) {
        this.dir = dir;
    }
}
