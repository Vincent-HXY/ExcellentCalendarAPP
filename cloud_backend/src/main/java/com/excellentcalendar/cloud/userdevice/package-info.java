/**
 * User profiles, preferences, registered devices and per-device synchronization state.
 *
 * <h3>Module structure</h3>
 * <ul>
 *   <li>{@code model} — JPA entities</li>
 *   <li>{@code repository} — Spring Data repositories</li>
 *   <li>{@code dto/request} — request payloads</li>
 *   <li>{@code dto/response} — response payloads</li>
 *   <li>{@code service} — business logic (profile CRUD, avatar upload)</li>
 *   <li>{@code web} — REST controllers and exception handlers</li>
 *   <li>{@code config} — security configuration</li>
 * </ul>
 */
@org.springframework.modulith.ApplicationModule(
        allowedDependencies = {"identity::service"}
)
package com.excellentcalendar.cloud.userdevice;