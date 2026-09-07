package com.excellentcalendar.excellent_calendar.bridge.sync

import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import org.junit.Assert.*
import org.junit.Test

class WorkspaceKeyVaultTest {
    private class Keys : WrappingKeyPort {
        val keys = mutableMapOf<String, SecretKey>(); var creations = 0
        override fun existing(identity: String) = keys[identity]
        override fun create(identity: String): SecretKey {
            check(!keys.containsKey(identity)); creations++
            return KeyGenerator.getInstance("AES").apply { init(256) }.generateKey().also { keys[identity] = it }
        }
        override fun delete(identity: String) { keys.remove(identity) }
    }
    @Test fun accountKeysAreIndependentAndWrongBindingOrMissingKeyFailsClosed() {
        val keys = Keys(); val vault = WorkspaceKeyVault(keys)
        val a = vault.create(ACCOUNT, "installation-A/workspace-A/schema-1".toByteArray())
        val b = vault.create(GUEST, "installation-A/workspace-B/schema-1".toByteArray())
        assertFalse(a.contentEquals(b)); assertEquals(2, keys.creations)
        failure("WORKSPACE_KEY_UNAVAILABLE") { vault.withKey(ACCOUNT, "wrong-installation".toByteArray(), a) {} }
        keys.delete(ACCOUNT)
        failure("WORKSPACE_KEY_UNAVAILABLE") { vault.withKey(ACCOUNT, "installation-A/workspace-A/schema-1".toByteArray(), a) {} }
        assertEquals(2, keys.creations)
    }
    @Test fun nativeKeyBufferIsWipedOnSuccessAndFailureAndTamperRejected() {
        val keys = Keys(); val vault = WorkspaceKeyVault(keys); val aad = "binding".toByteArray()
        val wrapped = vault.create(ACCOUNT, aad)
        var retained: ByteArray? = null
        vault.withKey(ACCOUNT, aad, wrapped) { assertEquals(32, it.size); retained = it }
        assertTrue(retained!!.all { it == 0.toByte() })
        try { vault.withKey(ACCOUNT, aad, wrapped) { retained = it; throw IllegalArgumentException() }; fail() }
        catch (_: IllegalArgumentException) { assertTrue(retained!!.all { it == 0.toByte() }) }
        wrapped[wrapped.lastIndex] = (wrapped.last().toInt() xor 1).toByte()
        failure("WORKSPACE_KEY_UNAVAILABLE") { vault.withKey(ACCOUNT, aad, wrapped) { fail("No native call") } }
    }
}
