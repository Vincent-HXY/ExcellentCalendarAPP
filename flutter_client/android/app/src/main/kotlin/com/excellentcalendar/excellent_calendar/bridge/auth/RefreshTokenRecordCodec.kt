package com.excellentcalendar.excellent_calendar.bridge.auth

import org.json.JSONException
import org.json.JSONObject


/**
 * Strict codec for the encrypted record payload. Malformed content always
 * fails explicitly; it never silently degrades to an empty record.
 */
object RefreshTokenRecordCodec {
    private val AllowedKeys = setOf("refresh_token", "session_id", "expires_at")

    fun encode(record: SecureRefreshTokenRecord): ByteArray =
        JSONObject()
            .put("refresh_token", record.refreshToken)
            .put("session_id", record.sessionId)
            .put("expires_at", record.expiresAt)
            .toString()
            .toByteArray(Charsets.UTF_8)

    fun decode(bytes: ByteArray): SecureRefreshTokenRecord {
        val text = try {
            String(bytes, Charsets.UTF_8)
        } catch (error: Exception) {
            throw RefreshTokenRecordCorruptedException(error)
        }
        val json = try {
            JSONObject(text)
        } catch (error: JSONException) {
            // JSONException 的 message 可能携带被解析的明文片段（内含 token），
            // 绝不能作为异常 cause 向外传播。
            throw RefreshTokenRecordCorruptedException()
        }
        if (json.length() != AllowedKeys.size) {
            throw RefreshTokenRecordCorruptedException()
        }
        for (key in json.keys()) {
            if (key !in AllowedKeys) {
                throw RefreshTokenRecordCorruptedException()
            }
        }
        val refreshToken = json.optString("refresh_token")
        val sessionId = json.optString("session_id")
        val expiresAt = json.optString("expires_at")
        if (refreshToken.length !in 32..8192) {
            throw RefreshTokenRecordCorruptedException()
        }
        if (!AuthRecordPatterns.isUuid(sessionId)) {
            throw RefreshTokenRecordCorruptedException()
        }
        if (!AuthRecordPatterns.isValidUtcDateTime(expiresAt)) {
            throw RefreshTokenRecordCorruptedException()
        }
        return SecureRefreshTokenRecord(refreshToken, sessionId, expiresAt)
    }
}