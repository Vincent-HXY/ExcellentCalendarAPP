package com.excellentcalendar.excellent_calendar.bridge.auth

import android.content.Context
import java.io.File
import java.io.IOException

/**
 * Keystore-encrypted Refresh Token file store in the app-private directory.
 *
 * The token file disappears together with the app data. Writes are atomic
 * (temp file + rename) and fsynced. The token value itself is never logged.
 */
class KeystoreRefreshTokenSecureStore(
    private val cipher: RefreshTokenCipher = KeystoreRefreshTokenCipher(),
    private val directory: File,
) : RefreshTokenSecureStore {
    private val file = File(directory, StorageFileName)

    override fun store(record: SecureRefreshTokenRecord) {
        try {
            val encoded = RefreshTokenRecordCodec.encode(record)
            val encrypted = cipher.encrypt(encoded)
            writeAtomically(encrypted)
        } catch (error: RefreshTokenRecordCorruptedException) {
            throw error
        } catch (error: RefreshTokenSecureStorageException) {
            throw error
        } catch (error: Exception) {
            throw RefreshTokenSecureStorageException(error)
        }
    }

    override fun read(): SecureRefreshTokenRecord? {
        if (!file.exists()) {
            return null
        }
        return try {
            val encrypted = file.readBytes()
            if (encrypted.isEmpty()) {
                throw RefreshTokenRecordCorruptedException()
            }
            val plain = cipher.decrypt(encrypted)
            RefreshTokenRecordCodec.decode(plain)
        } catch (error: RefreshTokenRecordCorruptedException) {
            throw error
        } catch (error: RefreshTokenSecureStorageException) {
            throw error
        } catch (error: Exception) {
            throw RefreshTokenSecureStorageException(error)
        }
    }

    override fun delete() {
        try {
            if (file.exists() && !file.delete()) {
                throw RefreshTokenSecureStorageException(IOException("delete failed"))
            }
        } catch (error: RefreshTokenSecureStorageException) {
            throw error
        } catch (error: Exception) {
            throw RefreshTokenSecureStorageException(error)
        }
    }

    override fun exists(): Boolean = file.exists()

    private fun writeAtomically(bytes: ByteArray) {
        if (!directory.exists() && !directory.mkdirs()) {
            throw RefreshTokenSecureStorageException(IOException("mkdir failed"))
        }
        val temp = File(directory, StorageFileName + ".tmp")
        temp.outputStream().use { stream ->
            stream.write(bytes)
            stream.fd.sync()
        }
        // 同目录 rename(2) 会原子替换已存在目标：先删旧文件会在“删除→改名”
        // 之间留下崩溃窗口（RT 丢失，表现为强制重登）。直接覆盖重命名。
        if (!temp.renameTo(file)) {
            throw RefreshTokenSecureStorageException(IOException("rename failed"))
        }
    }

    companion object {
        const val StorageFileName = "refresh_token_v1.bin"

        /** App-private directory that disappears together with the app data. */
        fun inAppDirectory(context: Context): File = File(context.filesDir, "auth")
    }
}
