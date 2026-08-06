package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.UseMainMethod;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.context.WebApplicationContext;

@ActiveProfiles("api")
@SpringBootTest(
        classes = ApiInfrastructureContextTest.MinimalSecurityConfig.class,
        webEnvironment = SpringBootTest.WebEnvironment.MOCK,
        useMainMethod = UseMainMethod.NEVER,
        properties = {
                "spring.autoconfigure.exclude="
                        + "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration,"
                        + "org.springframework.boot.hibernate.autoconfigure.HibernateJpaAutoConfiguration,"
                        + "org.springframework.boot.flyway.autoconfigure.FlywayAutoConfiguration",
                "spring.flyway.enabled=false"
        })
class ApiInfrastructureContextTest {

    @Configuration
    @EnableAutoConfiguration
    @ComponentScan(basePackages = {
            "com.excellentcalendar.cloud.platform.security",
            "com.excellentcalendar.cloud.platform.jwt",
            "com.excellentcalendar.cloud.platform.time",
            "com.excellentcalendar.cloud.platform.observability",
            "com.excellentcalendar.cloud.platform.mail",
            "com.excellentcalendar.cloud.platform.password"
    })
    static class MinimalSecurityConfig {
    }

    @Autowired
    private WebApplicationContext applicationContext;

    @Test
    void apiSecurityAndCorsInfrastructureStartsWithoutFakeDatabase() {
        assertThat(applicationContext.getBeansOfType(SecurityFilterChain.class)).hasSize(1);
        assertThat(applicationContext.getBean("corsConfigurationSource"))
                .isInstanceOf(CorsConfigurationSource.class);
        // UserDetailsService is auto-created by security, that's acceptable
    }

    @Test
    void healthIsPublicAndPlannedApiRoutesRemainClosed() throws Exception {
        MockMvc mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext)
                .apply(springSecurity())
                .build();

        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk());
        // Auth routes are not mapped in this minimal configuration
        mockMvc.perform(post("/api/v1/auth/login"))
                .andExpect(status().isNotFound());
    }
}