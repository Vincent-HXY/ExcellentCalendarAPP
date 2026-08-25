package com.excellentcalendar.cloud.media.api;

/**
 * RFC 9110 If-None-Match evaluation: a comma-separated list of entity tags (strong or weak) or
 * the "*" wildcard. Weak prefixes are ignored for comparison; a match means the client's cached
 * representation is still current (304).
 */
final class IfNoneMatch {

    private IfNoneMatch() {
    }

    static boolean matches(String header, String etag) {
        if (header == null || header.isBlank() || etag == null) {
            return false;
        }
        String comparable = stripWeakPrefix(etag);
        for (String token : header.split(",")) {
            String candidate = stripWeakPrefix(token.trim());
            if (candidate.equals("*") || candidate.equals(comparable)) {
                return true;
            }
        }
        return false;
    }

    private static String stripWeakPrefix(String value) {
        return value.startsWith("W/") ? value.substring(2) : value;
    }
}
