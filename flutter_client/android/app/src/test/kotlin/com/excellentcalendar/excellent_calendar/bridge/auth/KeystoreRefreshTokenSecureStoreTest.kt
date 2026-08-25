package com.excellentcalendar.excellent_calendar.bridge.auth

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class KeystoreRefreshTokenSecureStoreTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val record = SecureRefreshTokenRecord(
        refreshToken = "opaque-refresh-token-value-at-least-32-characters",
        sessionId = "62732653-c76a-40e7-bf72-bccabb54f06a",
        expiresAt = "2026-08-31T01:00:00Z",
    )

    private fun store(dir: File = folder.root, cipher: RefreshTokenCipher = FakeCipher()) =
        KeystoreRefreshTokenSecureStore(cipher, dir)

    @Test
    fun storeReadDeleteExistsRoundTrip() {
        val store = store()
        assertFalse(store.exists())

        store.store(record)
        assertTrue(store.exists())
        assertEquals(record, store.read())

        store.delete()
        assertFalse(store.exists())
        assertNull(store.read())
    }

    @Test
    fun storeOverwritesPreviousRecord() {
        val store = store()
        store.store(record)
        val updated = record.copy(refreshToken = "opaque-refresh-token-value-at-least-32-characters-2")
        store.store(updated)
        assertEquals(updated, store.read())
    }

    @Test
    fun corruptedFileFailsExplicitlyOnRead() {
        val store = store()
        val file = File(folder.root, KeystoreRefreshTokenSecureStore.StorageFileName)
        file.writeBytes(byteArrayOf(9, 8, 7))
        assertTrue(store.exists())
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            store.read()
        }
    }

    @Test
    fun storageExceptionIsWrappedWhenCipherFails() {
        val failing = object : RefreshTokenCipher {
            override fun encrypt(plaintext: ByteArray): ByteArray =
                throw RefreshTokenSecureStorageException(IllegalStateException("keystore unavailable"))

            override fun decrypt(payload: ByteArray): ByteArray = throw AssertionError("unexpected")
        }
        val store = store(cipher = failing)
        assertThrows(RefreshTokenSecureStorageException::class.java) {
            store.store(record)
        }
    }

    @Test
    fun corruptedCiphertextIsReportedAsCorrupted() {
        val cipher = object : RefreshTokenCipher {
            override fun encrypt(plaintext: ByteArray): ByteArray = byteArrayOf(1) + plaintext

            override fun decrypt(payload: ByteArray): ByteArray =
                throw RefreshTokenRecordCorruptedException(IllegalStateException("bad tag"))
        }
        val store = store(cipher = cipher)
        store.store(record)
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            store.read()
        }
    }

    private class FakeCipher : RefreshTokenCipher {
        override fun encrypt(plaintext: ByteArray): ByteArray = byteArrayOf(1) + plaintext

        override fun decrypt(payload: ByteArray): ByteArray {
            if (payload.isEmpty() || payload[0] != 1.toByte()) {
                throw RefreshTokenRecordCorruptedException()
            }
            return payload.copyOfRange(1, payload.size)
        }
    }
}
