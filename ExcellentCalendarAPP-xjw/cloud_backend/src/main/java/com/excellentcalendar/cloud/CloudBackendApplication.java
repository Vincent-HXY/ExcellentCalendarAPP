package com.excellentcalendar.cloud;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
//import org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration;
//import org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration;

@SpringBootApplication
@ConfigurationPropertiesScan
public class CloudBackendApplication {

    public static void main(String[] args) {
        SpringApplication.run(CloudBackendApplication.class, args);
    }
}
