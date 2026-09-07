package com.excellentcalendar.excellent_calendar.bridge.sync

import java.math.BigDecimal
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import org.json.JSONObject

/** Lexical guard before endpoint-specific frozen Schema validation; not a replacement for that validation. */
object StrictBoundary {
    private fun invalid(): Nothing = throw SyncLocalFailure("HTTP_ENVELOPE_INVALID")

    fun requireJson(bytes: ByteArray, maximumBytes: Int = 4_194_304): String {
        if (bytes.isEmpty() || bytes.size > maximumBytes) invalid()
        val text = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) { invalid() }
        Parser(text, false).parse()
        return text
    }

    fun envelope(
        bytes: ByteArray,
        version: Int,
        maximumBytes: Int = 4_194_304,
        validateFrozenError: ((JSONObject) -> Boolean)? = null,
    ): JSONObject {
        if (version !in setOf(1, 3)) invalid()
        val text = requireJson(bytes, maximumBytes)
        Parser(text, true).parse()
        val value = try { JSONObject(text) } catch (_: Exception) { invalid() }
        if (value.keys().asSequence().toSet() != setOf("ok", "data", "error", "contract_version", "request_id")) invalid()
        if (value.opt("ok") !is Boolean || value.opt("contract_version") !is Number ||
            value.get("contract_version").toString() != version.toString()) invalid()
        val requestId = value.opt("request_id") as? String ?: invalid()
        if (requestId.codePointCount(0, requestId.length) !in 1..128) invalid()
        if (value.getBoolean("ok")) {
            if (!value.isNull("error")) invalid()
        } else {
            if (!value.isNull("data") || value.opt("error") !is JSONObject) invalid()
            // Never accept an error until the adapter supplies its frozen code/retryability/context validator.
            if (validateFrozenError?.invoke(value.getJSONObject("error")) != true) invalid()
        }
        return value
    }

    private class Parser(private val input: String, private val safeCounters: Boolean) {
        private var offset = 0
        fun parse() { value(0); space(); if (offset != input.length) invalid() }
        private fun space() { while (offset < input.length && input[offset] in " \r\n\t") offset++ }
        private fun consume(char: Char): Boolean {
            space(); if (offset < input.length && input[offset] == char) { offset++; return true }; return false
        }
        private fun expect(char: Char) { if (!consume(char)) invalid() }
        private fun value(depth: Int) {
            if (depth > 64) invalid()
            space(); if (offset >= input.length) invalid()
            when (input[offset]) {
                '{' -> {
                    offset++; val keys = mutableSetOf<String>()
                    if (consume('}')) return
                    do { space(); if (offset >= input.length || input[offset] != '"') invalid()
                        if (!keys.add(string())) invalid()
                        expect(':'); value(depth + 1)
                    } while (consume(','))
                    expect('}')
                }
                '[' -> {
                    offset++; if (consume(']')) return
                    do { value(depth + 1) } while (consume(',')); expect(']')
                }
                '"' -> string()
                't' -> literal("true")
                'f' -> literal("false")
                'n' -> literal("null")
                else -> number()
            }
        }
        private fun literal(text: String) {
            if (!input.startsWith(text, offset)) invalid(); offset += text.length
        }
        private fun number() {
            val start = offset
            while (offset < input.length && input[offset] in "0123456789.eE+-") offset++
            val token = input.substring(start, offset)
            if (!token.matches(Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")) || token.length > 128) invalid()
            val number = try { BigDecimal(token) } catch (_: Exception) { invalid() }
            if (!token.toDouble().isFinite()) invalid()
            if (safeCounters && number.abs() > BigDecimal.valueOf(MAX_SYNC_COUNTER)) invalid()
        }
        private fun string(): String {
            expect('"'); val result = StringBuilder()
            var closed = false
            while (offset < input.length) {
                val char = input[offset++]
                if (char == '"') { closed = true; break }
                if (char.code < 32) invalid()
                if (char != '\\') { result.append(char); continue }
                if (offset == input.length) invalid()
                when (val escape = input[offset++]) {
                    '"', '\\', '/' -> result.append(escape)
                    'b' -> result.append('\b')
                    'f' -> result.append('\u000c')
                    'n' -> result.append('\n')
                    'r' -> result.append('\r')
                    't' -> result.append('\t')
                    'u' -> {
                        if (offset + 4 > input.length) invalid()
                        val hex = input.substring(offset, offset + 4)
                        if (!hex.matches(Regex("[0-9a-fA-F]{4}"))) invalid()
                        result.append(hex.toInt(16).toChar()); offset += 4
                    }
                    else -> invalid()
                }
            }
            if (!closed) invalid()
            val text = result.toString(); var index = 0
            while (index < text.length) {
                val char = text[index++]
                if (char.isHighSurrogate()) {
                    if (index == text.length || !text[index++].isLowSurrogate()) invalid()
                } else if (char.isLowSurrogate()) invalid()
            }
            return text
        }
    }
}
