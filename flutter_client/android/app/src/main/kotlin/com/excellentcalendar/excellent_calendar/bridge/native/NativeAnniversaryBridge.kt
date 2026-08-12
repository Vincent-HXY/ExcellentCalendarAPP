package com.excellentcalendar.excellent_calendar.bridge.native

/**
 * Narrow Kotlin access to the Anniversary module at the C++ Calendar Core boundary.
 *
 * Requests and responses remain Contract v2 JSON. Default implementations keep
 * existing module-specific test doubles source-compatible while the aggregate
 * bridge gains the Anniversary surface.
 */
interface NativeAnniversaryBridge {
    fun createAnniversary(requestJson: String): String =
        throw UnsupportedOperationException("anniversary.create is unavailable")

    fun updateAnniversary(requestJson: String): String =
        throw UnsupportedOperationException("anniversary.update is unavailable")

    fun deleteAnniversary(requestJson: String): String =
        throw UnsupportedOperationException("anniversary.delete is unavailable")

    fun getAnniversaryDetail(requestJson: String): String =
        throw UnsupportedOperationException("anniversary.detail is unavailable")

    fun listAnniversaries(requestJson: String): String =
        throw UnsupportedOperationException("anniversary.list is unavailable")

    fun previewAnniversaryCountdown(requestJson: String): String =
        throw UnsupportedOperationException("anniversary.preview_countdown is unavailable")
}
