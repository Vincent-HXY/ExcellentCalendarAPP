package com.excellentcalendar.excellent_calendar.bridge.auth

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore AES-256-GCM cipher. The master key never leaves the
 * Keystore; each encryption uses a fresh 12-byte IV prepended to the payload.
 */
class KeystoreRefreshTokenCipher : RefreshTokenCipher {
    companion object {
        private const val KeyAlias = "excellent_calendar_refresh_token_v1"
        private const val Transformation = "AES/GCM/NoPadding"
        private const val KeySizeBits = 256
        private const val IvSizeBytes = 12
        private const val TagSizeBits = 128
    }

    override fun encrypt(plaintext: ByteArray): ByteArray {
        try {
            val cipher = Cipher.getInstance(Transformation)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val encrypted = cipher.doFinal(plaintext)
            return cipher.iv + encrypted
        } catch (error: RefreshTokenRecordCorruptedException) {
            throw error
        } catch (error: Exception) {
            throw RefreshTokenSecureStorageException(error)
        }
    }

    override fun decrypt(payload: ByteArray): ByteArray {
        try {
            if (payload.size <= IvSizeBytes) {
                throw RefreshTokenRecordCorruptedException()
            }
            val iv = payload.copyOfRange(0, IvSizeBytes)
            val ciphertext = payload.copyOfRange(IvSizeBytes, payload.size)
            val cipher = Cipher.getInstance(Transformation)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(),
                GCMParameterSpec(TagSizeBits, iv),
            )
            return cipher.doFinal(ciphertext)
        } catch (error: AEADBadTagException) {
            throw RefreshTokenRecordCorruptedException(error)
        } catch (error: RefreshTokenRecordCorruptedException) {
            throw error
        } catch (error: Exception) {
            throw RefreshTokenSecureStorageException(error)
        }
    }

    private fun getOrCreateKey(): SecretKey {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            throw RefreshTokenSecureStorageException(IllegalStateException("Keystore AES-GCM requires API 23+"))
        }
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KeyAlias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KeyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(KeySizeBits)
                .build(),
        )
        return generator.generateKey()
    }
}
