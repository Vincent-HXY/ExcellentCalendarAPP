package com.excellentcalendar.excellent_calendar.bridge.sync

import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

internal fun contractRoot(): File {
    var directory: File? = File(System.getProperty("user.dir")).canonicalFile
    while (directory != null) {
        val contracts = File(directory, "contracts")
        if (File(contracts, "sync/sync_v1_revision_lock.json").isFile) return contracts
        directory = directory.parentFile
    }
    throw AssertionError("Repository Contract root unavailable")
}

class ContractPreflightTest {
    @Test fun defaultFrozenContractGateMustActuallyPass() {
        val contracts = contractRoot()
        val output = File.createTempFile("kotlin-sync-contract-", ".log")
        try {
            val process = ProcessBuilder("python", File(contracts, "run_sync_v1_validation.py").path)
                .directory(contracts.parentFile).redirectErrorStream(true).redirectOutput(output).start()
            if (!process.waitFor(60, TimeUnit.SECONDS)) {
                process.destroyForcibly(); fail("Contract gate timed out")
            }
            assertEquals(output.readText(), 0, process.exitValue())
        } finally { output.delete() }
    }

    @Test fun downstreamLockMustCoverCurrentNormalizedSourcesAndFixtureManifest() {
        val contracts = contractRoot()
        val lock = JSONObject(File(contracts, "sync/sync_v1_revision_lock.json").readText())
        val sources = lock.getJSONObject("sources_sha256")
        val changed = sources.keys().asSequence().filter { path ->
            sha256(File(contracts.parentFile, path).readText().replace("\r\n", "\n").replace("\r", "\n").toByteArray()) != sources.getString(path)
        }.toList()
        assertEquals("Contract owner must review amendments; do not regenerate a passing baseline", emptyList<String>(), changed)
        val manifest = File(contracts, "fixtures/sync/v1/manifest.json").readText().replace("\r\n", "\n").replace("\r", "\n").toByteArray()
        assertEquals(lock.getString("fixture_manifest_sha256"), sha256(manifest))
    }

    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }
}
