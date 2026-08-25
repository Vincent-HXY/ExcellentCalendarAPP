package com.excellentcalendar.excellent_calendar.bridge.auth

/**
 * AES-GCM payload cipher so the file store stays testable on the JVM.
 */
interface RefreshTokenCipher {
    fun encrypt(plaintext: ByteArray): ByteArray

    fun decrypt(payload: ByteArray): ByteArray
}
