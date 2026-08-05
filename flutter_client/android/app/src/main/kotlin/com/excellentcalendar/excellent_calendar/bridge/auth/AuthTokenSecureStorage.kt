package com.excellentcalendar.excellent_calendar.bridge.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.lang.ref.WeakReference

/**
 * EncryptedSharedPreferences-based secure storage for Refresh Token.
 *
 * Uses Android Keystore-backed MasterKey + AES-256 GCM encryption.
 * All operations are thread-safe and run on the caller's thread —
 * the caller (MethodChannel handler) is responsible for dispatching
 * to a background thread.
 *
 * On API 23+ this uses proper Keystore encryption.
 * Below API 23 the encryption is unavailable and a flag is set.
 */
class AuthTokenSecureStorage(context: Context) {

    private val contextRef = WeakReference(context.applicationContext)

    /** Whether the current device uses real Keystore encryption (API 23+). */
    val isSecure: Boolean
        get() = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M

    /**
     * Store the Refresh Token and associated session metadata.
     *
     * @return true if the write succeeded, false on storage error.
     */
    fun store(refreshToken: String, sessionId: String, expiresAt: String): Boolean {
        return try {
            prefs().edit()
                .putString(KEY_REFRESH_TOKEN, refreshToken)
                .putString(KEY_SESSION_ID, sessionId)
                .putString(KEY_EXPIRES_AT, expiresAt)
                .commit() // synchronous — ensures atomicity
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Read the stored Refresh Token record.
     *
     * @return a map with keys "refresh_token", "session_id", "expires_at",
     *         or null if no record exists.
     */
    fun read(): Map<String, String>? {
        return try {
            val prefs = prefs()
            val token = prefs.getString(KEY_REFRESH_TOKEN, null) ?: return null
            val sessionId = prefs.getString(KEY_SESSION_ID, null) ?: return null
            val expiresAt = prefs.getString(KEY_EXPIRES_AT, null) ?: return null
            linkedMapOf(
                "refresh_token" to token,
                "session_id" to sessionId,
                "expires_at" to expiresAt,
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Delete the stored Refresh Token record atomically.
     *
     * @return true if the deletion succeeded.
     */
    fun delete(): Boolean {
        return try {
            prefs().edit()
                .remove(KEY_REFRESH_TOKEN)
                .remove(KEY_SESSION_ID)
                .remove(KEY_EXPIRES_AT)
                .commit() // synchronous — ensures atomicity
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Check whether a Refresh Token record exists.
     */
    fun exists(): Boolean {
        return try {
            prefs().contains(KEY_REFRESH_TOKEN)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Returns the EncryptedSharedPreferences instance.
     *
     * On API 23+ this uses MasterKey.DEFAULT_MASTER_KEY_ALIAS which
     * is backed by Android Keystore (AES-256 GCM).
     *
     * On API 22 and below it falls back to a plain SharedPreferences
     * with an explicit warning in the file name.
     */
    private fun prefs(): SharedPreferences {
        val ctx = contextRef.get()
            ?: throw IllegalStateException("Application context has been garbage-collected")

        return if (isSecure) {
            val masterKey = MasterKey.Builder(ctx)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            EncryptedSharedPreferences.create(
                ctx,
                PREFS_FILE_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } else {
            // Insecure fallback for API < 23 — explicitly named to flag the risk.
            ctx.getSharedPreferences(PREFS_FILE_NAME_INSECURE, Context.MODE_PRIVATE)
        }
    }

    companion object {
        private const val PREFS_FILE_NAME = "excellent_calendar_auth_secure"
        private const val PREFS_FILE_NAME_INSECURE = "excellent_calendar_auth_INSECURE_api22"

        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_EXPIRES_AT = "expires_at"
    }
}