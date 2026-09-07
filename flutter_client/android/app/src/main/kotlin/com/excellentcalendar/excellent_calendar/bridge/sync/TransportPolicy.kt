package com.excellentcalendar.excellent_calendar.bridge.sync

import java.net.URI

/** URL policy is an early check; a real transport must additionally enforce DNS/TLS at connection time. */
object EndpointPolicy {
    fun requireBaseUrl(value: String, debug: Boolean): URI {
        val uri = try { URI(value) } catch (_: Exception) { throw SyncLocalFailure("ENDPOINT_INVALID") }
        val host = uri.host?.lowercase() ?: throw SyncLocalFailure("ENDPOINT_INVALID")
        fun reject(): Nothing = throw SyncLocalFailure("ENDPOINT_INVALID")
        if (uri.userInfo != null || uri.rawQuery != null || uri.rawFragment != null ||
            uri.rawPath !in listOf("", "/") || uri.port !in -1..65535 || uri.port == 0 || value != value.trim()) reject()
        val octets = host.split('.').takeIf { it.size == 4 }?.map { part ->
            part.takeIf { it.matches(Regex("0|[1-9][0-9]{0,2}")) }?.toIntOrNull()
        }
        val ipv4 = octets?.takeIf { values -> values.all { it != null && it in 0..255 } }?.map { it!! }
        val privateIp = ipv4 != null && (ipv4[0] == 10 || (ipv4[0] == 172 && ipv4[1] in 16..31) ||
            (ipv4[0] == 192 && ipv4[1] == 168))
        if (debug && uri.scheme == "http" && privateIp) return uri
        if (uri.scheme != "https" || ipv4 != null || host.contains(':') || !host.contains('.')) reject()
        if (host.endsWith(".local") || host.endsWith(".localhost") || host.endsWith(".internal") ||
            host.split('.').any { !it.matches(Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")) } ||
            !host.substringAfterLast('.').matches(Regex("[a-z]{2,63}"))) reject()
        return uri
    }
}

/** The injected sampler returns a uniform value in the inclusive [0, maximum] interval. */
class RetryPolicy(private val sampleMillis: (Long) -> Long) {
    fun retryableStatus(status: Int) = status in setOf(429, 500, 502, 503, 504)

    fun delayMillis(attempt: Int, retryAfterSeconds: Int?, retryAfterHeader: String?): Long? {
        if (attempt < 0 || retryAfterSeconds != null && retryAfterSeconds !in 1..86400 ||
            retryAfterHeader != null && (retryAfterSeconds == null || retryAfterHeader != retryAfterSeconds.toString())) {
            throw SyncLocalFailure("HTTP_ENVELOPE_INVALID")
        }
        if (attempt >= 8) return null
        val ceiling = minOf(900_000L, 5_000L shl attempt)
        val jitter = sampleMillis(ceiling)
        require(jitter in 0..ceiling)
        return minOf(86_400_000L, maxOf(jitter, (retryAfterSeconds ?: 0) * 1000L))
    }
}
