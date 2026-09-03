package com.excellentcalendar.excellent_calendar.android.search

import com.excellentcalendar.excellent_calendar.bridge.contract.SearchContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchTextContract
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

data class SearchHistorySnapshot(
    val revision: Long,
    val items: List<String>,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "revision" to revision,
        "items" to items,
    )
}

internal sealed interface SearchHistoryDecodeResult {
    data class KnownV1(
        val snapshot: SearchHistorySnapshot,
        val needsRepair: Boolean,
        val corruptionCategory: String?,
    ) : SearchHistoryDecodeResult

    data class UnsupportedVersion(val version: Long) : SearchHistoryDecodeResult
    data class Unreadable(val category: String) : SearchHistoryDecodeResult
}

/** Codec for the one versioned, ordered history file. It never logs or exposes stored text. */
internal object SearchHistoryCodec {
    fun decode(bytes: ByteArray): SearchHistoryDecodeResult {
        if (bytes.size > MaximumFileBytes) return SearchHistoryDecodeResult.Unreadable("file_too_large")
        val json = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(java.nio.ByteBuffer.wrap(bytes))
                .toString()
        } catch (_: CharacterCodingException) {
            return SearchHistoryDecodeResult.Unreadable("invalid_utf8")
        }
        val root = try {
            JSONObject(json)
        } catch (_: JSONException) {
            return SearchHistoryDecodeResult.Unreadable("malformed_json")
        }
        val version = exactLong(root.opt("schema_version"))
            ?: return SearchHistoryDecodeResult.Unreadable("invalid_schema_version")
        if (version != SchemaVersion) {
            return if (version > SchemaVersion) {
                SearchHistoryDecodeResult.UnsupportedVersion(version)
            } else {
                SearchHistoryDecodeResult.Unreadable("unsupported_legacy_version")
            }
        }
        val revision = exactLong(root.opt("revision"))
        if (revision == null || revision !in 0..SearchContracts.MaximumSafeInteger) {
            return SearchHistoryDecodeResult.Unreadable("invalid_revision")
        }
        val keywords = root.opt("keywords") as? JSONArray
            ?: return SearchHistoryDecodeResult.Unreadable("invalid_keywords_container")

        var needsRepair = root.keys().asSequence().toSet() != Fields
        var category: String? = if (needsRepair) "unexpected_fields" else null
        val normalized = ArrayList<String>(minOf(keywords.length(), SearchContracts.MaximumHistoryItems))
        val identities = mutableSetOf<String>()
        for (index in 0 until keywords.length()) {
            val raw = keywords.opt(index)
            if (raw !is String || !SearchTextContract.hasValidScalars(raw)) {
                needsRepair = true
                category = category ?: "invalid_item"
                continue
            }
            val canonical = SearchTextContract.normalize(raw)
            val valid = canonical.isNotEmpty() &&
                SearchTextContract.scalarCount(canonical) <= MaximumKeywordScalars &&
                SearchTextContract.utf8Length(canonical) <= MaximumKeywordUtf8Bytes
            if (!valid) {
                needsRepair = true
                category = category ?: "invalid_item"
                continue
            }
            val identity = SearchTextContract.asciiFold(canonical)
            if (!identities.add(identity)) {
                needsRepair = true
                category = category ?: "duplicate_item"
                continue
            }
            if (canonical != raw) {
                needsRepair = true
                category = category ?: "noncanonical_item"
            }
            if (normalized.size < SearchContracts.MaximumHistoryItems) {
                normalized += canonical
            } else {
                needsRepair = true
                category = category ?: "too_many_items"
            }
        }
        return SearchHistoryDecodeResult.KnownV1(
            SearchHistorySnapshot(revision, normalized),
            needsRepair,
            category,
        )
    }

    fun encode(snapshot: SearchHistorySnapshot): ByteArray {
        SearchTextContract.requireCanonicalHistory(snapshot.items, "SearchHistory.keywords")
        require(snapshot.revision in 0..SearchContracts.MaximumSafeInteger)
        val root = JSONObject()
        root.put("schema_version", SchemaVersion)
        root.put("revision", snapshot.revision)
        root.put("keywords", JSONArray(snapshot.items))
        return root.toString().toByteArray(Charsets.UTF_8)
    }

    private fun exactLong(value: Any?): Long? = when (value) {
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    private const val SchemaVersion = 1L
    private const val MaximumKeywordScalars = 128
    private const val MaximumKeywordUtf8Bytes = 512
    private const val MaximumFileBytes = 65_536
    private val Fields = setOf("schema_version", "revision", "keywords")
}
