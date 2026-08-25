package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.auth.AuthRecordPatterns
import com.excellentcalendar.excellent_calendar.bridge.auth.SecureRefreshTokenRecord

/**
 * Strict validators for the auth.refresh_token.* MethodChannel payloads
 * (contracts/method_channels.yaml, Native Contract v2).
 */
internal object AuthRefreshTokenContracts {
    private val AllowedKeys = setOf("refresh_token", "session_id", "expires_at")

    fun storeRequest(value: Any?): SecureRefreshTokenRecord = parseRecord(
        value,
        "StoreRefreshTokenRequest",
    )

    private fun parseRecord(value: Any?, parent: String): SecureRefreshTokenRecord {
        if (value !is Map<*, *>) {
            throw NativeContractViolation("$parent must be an object.", parent)
        }
        @Suppress("UNCHECKED_CAST")
        val map = value as Map<String, Any?>
        ContractValidators.rejectUnknownFields(map, AllowedKeys, parent)
        ContractValidators.requireString(map, "refresh_token", parent, nonEmpty = true)
        ContractValidators.requireString(map, "session_id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "expires_at", parent, nonEmpty = true)

        val refreshToken = map["refresh_token"] as String
        val sessionId = map["session_id"] as String
        val expiresAt = map["expires_at"] as String
        if (refreshToken.length !in 32..8192) {
            throw NativeContractViolation("$parent.refresh_token must be a 32..8192 string.", "$parent.refresh_token")
        }
        if (!AuthRecordPatterns.isUuid(sessionId)) {
            throw NativeContractViolation("$parent.session_id must be a UUID.", "$parent.session_id")
        }
        if (!AuthRecordPatterns.isValidUtcDateTime(expiresAt)) {
            throw NativeContractViolation("$parent.expires_at must be an ISO 8601 UTC instant.", "$parent.expires_at")
        }
        return SecureRefreshTokenRecord(refreshToken, sessionId, expiresAt)
    }

    /** common/native_operation_response.schema.json */
    fun operationResponse(performed: Boolean = true, message: String? = null): Map<String, Any?> =
        linkedMapOf(
            "performed" to performed,
            "message" to message,
        )

    /** auth/refresh_token_presence_response.schema.json */
    fun presenceResponse(exists: Boolean): Map<String, Any?> = linkedMapOf("exists" to exists)

    /** auth/secure_refresh_token_record_response.schema.json */
    fun secureRecordResponse(record: SecureRefreshTokenRecord): Map<String, Any?> =
        linkedMapOf(
            "refresh_token" to record.refreshToken,
            "session_id" to record.sessionId,
            "expires_at" to record.expiresAt,
        )
}