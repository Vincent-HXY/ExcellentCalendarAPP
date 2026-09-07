package com.excellentcalendar.excellent_calendar.bridge.sync

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface WrappingKeyPort {
    fun existing(identity: String): SecretKey?
    fun create(identity: String): SecretKey
    fun delete(identity: String)
}

/** Raw wrapped bytes are stored by the lifecycle's AEAD AtomicFile owner, never by a MethodChannel DTO. */
class WorkspaceKeyVault(private val keys: WrappingKeyPort) {
    fun create(identity: String, aad: ByteArray): ByteArray {
        val dek = ByteArray(32)
        try {
            if (keys.existing(identity) != null || aad.isEmpty()) throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE")
            SecureRandom().nextBytes(dek)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, keys.create(identity))
            cipher.updateAAD(aad)
            if (cipher.iv.size != 12) throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE")
            return byteArrayOf(1) + cipher.iv + cipher.doFinal(dek)
        } catch (_: Exception) { throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE") }
        finally { dek.fill(0) }
    }

    fun <T> withKey(identity: String, aad: ByteArray, wrapped: ByteArray, nativeCall: (ByteArray) -> T): T {
        val dek = try {
            if (wrapped.size != 61 || wrapped[0] != 1.toByte() || aad.isEmpty()) throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE")
            val key = keys.existing(identity) ?: throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, wrapped, 1, 12))
            cipher.updateAAD(aad)
            cipher.doFinal(wrapped, 13, wrapped.size - 13)
        } catch (_: Exception) { throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE") }
        try {
            if (dek.size != 32) throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE")
            return nativeCall(dek)
        } finally { dek.fill(0) }
    }
}
