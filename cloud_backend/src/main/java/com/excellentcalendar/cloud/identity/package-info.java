/**
 * Accounts, password credentials, email challenges, sessions and Refresh Token rotation.
 *
 * <h3>Module structure</h3>
 * <ul>
 *   <li>{@code model} — JPA entities</li>
 *   <li>{@code repository} — Spring Data repositories</li>
 *   <li>{@code dto/request} — request payloads</li>
 *   <li>{@code dto/response} — response payloads</li>
 *   <li>{@code service} — business logic (JWT, authentication, profile, email)</li>
 *   <li>{@code web} — REST controllers and exception handlers</li>
 *   <li>{@code config} — properties and security configuration</li>
 * </ul>
 */
@org.springframework.modulith.ApplicationModule(
        allowedDependencies = {"platform::security"}
)
package com.excellentcalendar.cloud.identity;