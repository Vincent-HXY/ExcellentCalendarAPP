package com.excellentcalendar.cloud.media.api;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * RFC 9110 If-None-Match semantics: list matching, "*" wildcard and weak-tag prefixes.
 */
class IfNoneMatchTest {

    @Test
    void exactTagMatches() {
        assertThat(IfNoneMatch.matches("\"abc\"", "\"abc\"")).isTrue();
        assertThat(IfNoneMatch.matches("\"abc\"", "\"abd\"")).isFalse();
    }

    @Test
    void matchesAnyElementOfAList() {
        assertThat(IfNoneMatch.matches("\"other\", \"abc\"", "\"abc\"")).isTrue();
        assertThat(IfNoneMatch.matches("\"other\",\"abc\"", "\"abc\"")).isTrue();
    }

    @Test
    void wildcardMatchesAnything() {
        assertThat(IfNoneMatch.matches("*", "\"abc\"")).isTrue();
    }

    @Test
    void weakPrefixIsIgnoredForComparison() {
        assertThat(IfNoneMatch.matches("W/\"abc\"", "\"abc\"")).isTrue();
    }

    @Test
    void blankOrNullHeaderNeverMatches() {
        assertThat(IfNoneMatch.matches(null, "\"abc\"")).isFalse();
        assertThat(IfNoneMatch.matches("  ", "\"abc\"")).isFalse();
    }

    @Test
    void substringCoincidenceDoesNotMatch() {
        // The old String.contains check would have matched this pair.
        assertThat(IfNoneMatch.matches("\"abc12\"", "\"abc\"")).isFalse();
    }
}
