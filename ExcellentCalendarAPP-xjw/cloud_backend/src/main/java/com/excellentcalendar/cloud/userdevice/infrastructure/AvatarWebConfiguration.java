package com.excellentcalendar.cloud.userdevice.infrastructure;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Configures static resource serving for avatar files.
 * Maps {@code /avatars/**} to the configured upload directory.
 */
@Profile("api")
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(AvatarProperties.class)
public class AvatarWebConfiguration implements WebMvcConfigurer {

    private final AvatarProperties properties;

    public AvatarWebConfiguration(AvatarProperties properties) {
        this.properties = properties;
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        String uploadDirPath = properties.getUploadDir().toAbsolutePath().toUri().toString();
        registry.addResourceHandler("/avatars/**")
                .addResourceLocations(uploadDirPath)
                .setCachePeriod(86400); // 24 hours
    }
}