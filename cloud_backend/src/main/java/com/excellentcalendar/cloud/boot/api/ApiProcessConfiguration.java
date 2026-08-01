package com.excellentcalendar.cloud.boot.api;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Profile("api")
@Configuration(proxyBeanMethods = false)
class ApiProcessConfiguration {
}
