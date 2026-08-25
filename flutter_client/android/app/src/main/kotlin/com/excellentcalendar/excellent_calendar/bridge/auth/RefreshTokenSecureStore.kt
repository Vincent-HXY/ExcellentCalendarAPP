package com.excellentcalendar.excellent_calendar.bridge.auth

/**
 * Sensitive Refresh Token record. This value must never be logged.
 */
data class SecureRefreshTokenRecord(
    val refreshToken: String,
    val sessionId: String,
    val expiresAt: String,
)

/** No Refresh Token record exists in Android secure storage. */
class RefreshTokenRecordNotFoundException :
    Exception("No Refresh Token record exists in Android secure storage.")

/** The encrypted record cannot be decoded safely. */
class RefreshTokenRecordCorruptedException(cause: Throwable? = null) :
    Exception("The encrypted Refresh Token record cannot be decoded safely.", cause)

/** Android secure storage could not persist or delete the Refresh Token. */
class RefreshTokenSecureStorageException(cause: Throwable? = null) :
    Exception("Android secure storage could not persist or delete the Refresh Token.", cause)

/**
 * Android-local storage for exactly one Refresh Token record. It performs no
 * login business logic: only store / read / delete / exists.
 */
interface RefreshTokenSecureStore {
    fun store(record: SecureRefreshTokenRecord)

    /** Returns null when no record exists; throws Corrupted/Storage failures. */
    fun read(): SecureRefreshTokenRecord?

    fun delete()

    fun exists(): Boolean
}
