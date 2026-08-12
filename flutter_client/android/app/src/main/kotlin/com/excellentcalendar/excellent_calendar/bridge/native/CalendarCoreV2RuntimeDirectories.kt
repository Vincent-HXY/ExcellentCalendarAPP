package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

internal class CalendarCoreV2RuntimeRequestProvider(
    context: Context,
) : NativeRuntimeRequestProvider {
    private val applicationContext = context.applicationContext

    override fun createRequestJson(): String {
        val storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(applicationContext.filesDir)
        val tzdbDirectory = BundledTzdbExtractor.extract(applicationContext)
        return NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "storage_directory" to storageDirectory.absolutePath,
                "tzdb_directory" to tzdbDirectory.absolutePath,
            ),
        )
    }
}

/**
 * Resolves the Contract-owned active path without mutating storage.
 *
 * The C++ v2 bootstrap must be the only component that validates and discards a
 * formal v1 directory before creating the empty v2 stores at the same path.
 * V1 data is not preserved.
 */
internal object CalendarCoreV2StorageDirectoryResolver {
    private const val LocalStorageDirectoryName = "local_storage"
    private const val ActiveStorageDirectoryName = "calendar_core_storage_json"

    fun resolve(filesDir: File): File {
        val active = File(File(filesDir, LocalStorageDirectoryName), ActiveStorageDirectoryName)

        if (active.exists() && !active.isDirectory) {
            throw IOException("Calendar Core v2 storage path is not a directory: ${active.absolutePath}")
        }
        return active
    }
}

internal object BundledTzdbExtractor {
    const val Version = "2026c"
    private const val AssetRoot = Version
    private const val TzdbDirectoryName = "tzdb"

    @Synchronized
    fun extract(context: Context): File {
        val parent = File(context.filesDir, TzdbDirectoryName)
        val destination = File(parent, Version)
        if (isComplete(destination)) return destination

        if (!parent.exists() && !parent.mkdirs()) {
            throw IOException("Cannot create TZDB parent directory: ${parent.absolutePath}")
        }
        val staging = File(parent, ".$Version-${UUID.randomUUID()}")
        if (!staging.mkdirs()) {
            throw IOException("Cannot create TZDB staging directory: ${staging.absolutePath}")
        }
        try {
            copyAssetTree(context, AssetRoot, staging)
            if (!isComplete(staging)) {
                throw IOException("Bundled TZDB is incomplete or is not version $Version.")
            }
            if (destination.exists() && !destination.deleteRecursively()) {
                throw IOException("Cannot replace incomplete TZDB directory.")
            }
            if (!staging.renameTo(destination)) {
                throw IOException("Atomic TZDB installation failed.")
            }
            return destination
        } finally {
            if (staging.exists()) staging.deleteRecursively()
        }
    }

    private fun isComplete(directory: File): Boolean =
        directory.isDirectory &&
            File(directory, "version").takeIf(File::isFile)?.readText()?.trim() == Version &&
            File(directory, "europe").isFile &&
            File(directory, "asia").isFile

    private fun copyAssetTree(context: Context, assetPath: String, destination: File) {
        val children = context.assets.list(assetPath)
            ?: throw IOException("Cannot list bundled asset: $assetPath")
        if (children.isEmpty()) {
            destination.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                FileOutputStream(destination).use { output -> input.copyTo(output) }
            }
            return
        }
        if (!destination.exists() && !destination.mkdirs()) {
            throw IOException("Cannot create TZDB asset directory: ${destination.absolutePath}")
        }
        for (child in children) {
            copyAssetTree(context, "$assetPath/$child", File(destination, child))
        }
    }
}
