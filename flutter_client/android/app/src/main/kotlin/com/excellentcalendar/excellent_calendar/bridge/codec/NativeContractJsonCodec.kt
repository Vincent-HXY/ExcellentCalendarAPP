package com.excellentcalendar.excellent_calendar.bridge.codec

import org.json.JSONArray
import org.json.JSONObject

object NativeContractJsonCodec {
    fun encodeObject(value: Map<String, Any?>): String {
        return (toJsonCompatible(value) as JSONObject).toString()
    }

    fun decodeObject(json: String): Map<String, Any?> {
        return fromJsonObject(JSONObject(json))
    }

    fun normalizeMap(value: Any?): Map<String, Any?> {
        val normalized = normalize(value)
        if (normalized is Map<*, *>) {
            val result = linkedMapOf<String, Any?>()
            for ((key, entryValue) in normalized) {
                if (key !is String) {
                    throw IllegalArgumentException("JSON object keys must be strings.")
                }
                result[key] = entryValue
            }
            return result
        }
        throw IllegalArgumentException("MethodChannel arguments must be a JSON object.")
    }

    fun normalize(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is String, is Boolean -> value
            is Int, is Long, is Double -> value
            is Float -> value.toDouble()
            is Short -> value.toInt()
            is Byte -> value.toInt()
            is Map<*, *> -> {
                val result = linkedMapOf<String, Any?>()
                for ((key, entryValue) in value) {
                    if (key !is String) {
                        throw IllegalArgumentException("JSON object keys must be strings.")
                    }
                    result[key] = normalize(entryValue)
                }
                result
            }
            is Iterable<*> -> value.map { normalize(it) }
            is Array<*> -> value.map { normalize(it) }
            else -> throw IllegalArgumentException("Unsupported JSON value type: ${value.javaClass.name}")
        }
    }

    private fun fromJsonObject(jsonObject: JSONObject): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>()
        val keys = jsonObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = fromJsonValue(jsonObject.get(key))
        }
        return result
    }

    private fun fromJsonArray(jsonArray: JSONArray): List<Any?> {
        val result = ArrayList<Any?>(jsonArray.length())
        for (index in 0 until jsonArray.length()) {
            result.add(fromJsonValue(jsonArray.get(index)))
        }
        return result
    }

    private fun fromJsonValue(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> fromJsonObject(value)
            is JSONArray -> fromJsonArray(value)
            is String, is Boolean, is Int, is Long, is Double -> value
            is Number -> value
            else -> throw IllegalArgumentException("Unsupported native JSON value type: ${value.javaClass.name}")
        }
    }

    private fun toJsonCompatible(value: Any?): Any? {
        return when (value) {
            null -> JSONObject.NULL
            is String, is Boolean, is Int, is Long, is Double -> value
            is Float -> value.toDouble()
            is Short -> value.toInt()
            is Byte -> value.toInt()
            is Map<*, *> -> {
                val json = JSONObject()
                for ((key, entryValue) in value) {
                    require(key is String) { "JSON object keys must be strings." }
                    json.put(key, toJsonCompatible(entryValue))
                }
                json
            }
            is Iterable<*> -> {
                val json = JSONArray()
                value.forEach { json.put(toJsonCompatible(it)) }
                json
            }
            is Array<*> -> {
                val json = JSONArray()
                value.forEach { json.put(toJsonCompatible(it)) }
                json
            }
            else -> throw IllegalArgumentException("Unsupported JSON value type: ${value.javaClass.name}")
        }
    }
}
