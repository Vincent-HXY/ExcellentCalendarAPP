package com.excellentcalendar.cloud.platform.time;

import java.util.UUID;

/**
 * Injectable entity-ID source so tests can assert stable identities.
 */
@FunctionalInterface
public interface IdGenerator {

    UUID next();
}
