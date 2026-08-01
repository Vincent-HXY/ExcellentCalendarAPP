package com.excellentcalendar.cloud.boot.worker;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

/**
 * Worker process assembly point. Consumers are added only together with a durable queue contract.
 */
@Profile("worker")
@Configuration(proxyBeanMethods = false)
class WorkerProcessConfiguration {
}
