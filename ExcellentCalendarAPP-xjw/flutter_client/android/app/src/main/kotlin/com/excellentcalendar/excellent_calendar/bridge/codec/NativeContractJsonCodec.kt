package com.excellentcalendar.excellent_calendar.bridge.codec

import org.json.JSONArray
import org.json.JSONObject

/**
 * Kotlin/Flutter/C++ 边界使用的 JSON 编解码工具。
 *
 * Kotlin 初学点：
 * - `object` 声明的是单例对象，整个进程只有一个实例，适合放无状态工具函数。
 * - `Any?` 表示“任意类型并且允许为 null”。跨语言数据在刚进入 Kotlin 时类型不确定，
 *   所以先用 `Any?` 接住，再逐层校验。
 *
 * 这个工具类做两件事：
 * 1. 把 MethodChannel 传来的 Map/List/基本类型标准化成 JSON 兼容结构。
 * 2. 把 C++ 返回的 JSON 字符串解析成 Kotlin Map/List/基本类型。
 */
object NativeContractJsonCodec {
    /** 把 Kotlin Map 编码成 JSON object 字符串。 */
    fun encodeObject(value: Map<String, Any?>): String {
        return (toJsonCompatible(value) as JSONObject).toString()
    }

    /** 把 JSON object 字符串解码为 Kotlin Map。 */
    fun decodeObject(json: String): Map<String, Any?> {
        return fromJsonObject(JSONObject(json))
    }

    /**
     * 把 MethodChannel 参数整理成 `Map<String, Any?>`。
     *
     * Flutter MethodChannel 传来的对象运行时类型可能是 LinkedHashMap、ArrayList 等。
     * 业务合约希望顶层一定是 JSON object，所以这里如果不是 Map 就直接报错。
     */
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

    /**
     * 递归规范化任意 JSON-like 值。
     *
     * `when` 是 Kotlin 的模式匹配表达式，类似更强大的 switch。
     * 这里把 Short/Byte/Float 转成 JSON 更常用的 Int/Double，避免跨语言数字类型不一致。
     */
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

    /** 递归读取 JSONObject，保持字段顺序使用 linkedMapOf，便于日志和测试更稳定。 */
    private fun fromJsonObject(jsonObject: JSONObject): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>()
        val keys = jsonObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = fromJsonValue(jsonObject.get(key))
        }
        return result
    }

    /** 把 JSONArray 转成 Kotlin List。`0 until length` 生成左闭右开的整数区间。 */
    private fun fromJsonArray(jsonArray: JSONArray): List<Any?> {
        val result = ArrayList<Any?>(jsonArray.length())
        for (index in 0 until jsonArray.length()) {
            result.add(fromJsonValue(jsonArray.get(index)))
        }
        return result
    }

    /** 把 org.json 的对象模型递归转回 Kotlin 对象模型。 */
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

    /** 把 Kotlin 对象模型递归转成 org.json 可接受的对象模型。 */
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
