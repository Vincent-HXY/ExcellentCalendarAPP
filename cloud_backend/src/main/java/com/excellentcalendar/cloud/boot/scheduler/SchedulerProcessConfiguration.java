package com.excellentcalendar.cloud.boot.scheduler;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Scheduler process assembly point. Scheduled jobs must use database claims or leases.
 */
@Profile("scheduler")
@EnableScheduling
@Configuration(proxyBeanMethods = false)
class SchedulerProcessConfiguration {
}
