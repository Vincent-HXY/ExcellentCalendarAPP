// Kotlin assertions are evaluated here; strict JVM JSON/JCS is shared with Java.
import java.io.File
import java.time.LocalDate
import java.time.OffsetDateTime
import java.util.UUID
import java.util.regex.Pattern

private class KotlinAssertions(val nodes: List<*>) {
    private fun type(name: String, value: Any?): Boolean = when (name) {
        "null" -> value == null
        "boolean" -> value is Boolean
        "object" -> value is Map<*, *>
        "array" -> value is List<*>
        "string" -> value is String
        "number" -> value is Double && value.isFinite()
        "integer" -> value is Double && value.isFinite() && value == Math.rint(value)
        else -> error("Unsupported type")
    }
    private fun same(a: Any?, b: Any?) = SchemaProbeJson.canonical(a) == SchemaProbeJson.canonical(b)
    private fun matches(pattern: String, value: String) = Pattern.compile(pattern, Pattern.UNICODE_CHARACTER_CLASS).matcher(value).find()
    private fun format(name: String, value: String): Boolean = try {
        when (name) {
            "date" -> LocalDate.parse(value).toString() == value
            "date-time" -> { OffsetDateTime.parse(value.uppercase()); true }
            "uuid" -> value.length == 36 && UUID.fromString(value).toString().equals(value, ignoreCase = true)
            "email" -> '@' in value
            else -> error("Unsupported format")
        }
    } catch (_: IllegalArgumentException) { false } catch (_: java.time.DateTimeException) { false }
    @Suppress("UNCHECKED_CAST")
    fun valid(index: Int, value: Any?, depth: Int = 0): Boolean {
        if (depth > 256) return false
        val rule = nodes[index] as Map<String, Any?>
        fun child(index: Any?, value: Any?) = valid((index as Double).toInt(), value, depth + 1)
        fun smaller(name: String, actual: Int) = rule[name]?.let { actual < it as Double } ?: false
        fun larger(name: String, actual: Int) = rule[name]?.let { actual > it as Double } ?: false
        if (rule.containsKey("boolean")) return rule["boolean"] as Boolean
        if (rule.containsKey("ref") && !child(rule["ref"], value)) return false
        rule["type"]?.let { types ->
            if (types is String && !type(types, value)) return false
            if (types is List<*> && types.none { type(it as String, value) }) return false
        }
        if (rule.containsKey("const") && !same(rule["const"], value)) return false
        rule["enum"]?.let { if ((it as List<*>).none { item -> same(item, value) }) return false }
        for (name in listOf("allOf", "anyOf", "oneOf")) rule[name]?.let {
            val list = it as List<*>; val count = list.count { item -> child(item, value) }
            if (name == "allOf" && count != list.size || name == "anyOf" && count == 0 || name == "oneOf" && count != 1) return false
        }
        if (rule.containsKey("not") && child(rule["not"], value)) return false
        if (rule.containsKey("if")) {
            val branch = if (child(rule["if"], value)) "then" else "else"
            if (rule.containsKey(branch) && !child(rule[branch], value)) return false
        }
        if (value is Double) {
            rule["minimum"]?.let { if (value < it as Double) return false }
            rule["maximum"]?.let { if (value > it as Double) return false }
        }
        if (value is String) {
            val length = value.codePointCount(0, value.length)
            if (smaller("minLength", length) || larger("maxLength", length)) return false
            rule["pattern"]?.let { if (!matches(it as String, value)) return false }
            rule["format"]?.let { if (!format(it as String, value)) return false }
        }
        if (value is List<*>) {
            if (smaller("minItems", value.size) || larger("maxItems", value.size)) return false
            if (rule["uniqueItems"] == true && value.map { SchemaProbeJson.canonical(it) }.toSet().size != value.size) return false
            rule["items"]?.let { if (value.any { item -> !child(it, item) }) return false }
        }
        if (value is Map<*, *>) {
            if (smaller("minProperties", value.size) || larger("maxProperties", value.size)) return false
            rule["required"]?.let { if ((it as List<*>).any { key -> !value.containsKey(key) }) return false }
            val properties = (rule["properties"] ?: emptyMap<String, Any?>()) as Map<String, Any?>
            val patterns = (rule["patternProperties"] ?: emptyMap<String, Any?>()) as Map<String, Any?>
            for ((key, member) in value) {
                key as String
                var matched = properties.containsKey(key)
                if (matched && !child(properties[key], member)) return false
                for ((pattern, node) in patterns) if (matches(pattern, key)) { matched = true; if (!child(node, member)) return false }
                if (!matched && rule.containsKey("additionalProperties") && !child(rule["additionalProperties"], member)) return false
                if (rule.containsKey("propertyNames") && !child(rule["propertyNames"], key)) return false
            }
            rule["dependentRequired"]?.let { dependencies ->
                for ((key, required) in dependencies as Map<String, List<String>>) {
                    if (value.containsKey(key) && required.any { !value.containsKey(it) }) return false
                }
            }
        }
        return true
    }
}

fun main(args: Array<String>) {
    val bundle = SchemaProbeJson.parse(File(args[0]).readText(Charsets.UTF_8)) as Map<*, *>
    val assertions = KotlinAssertions(bundle["nodes"] as List<*>)
    for (entry in bundle["cases"] as List<*>) {
        try {
            val case = entry as Map<*, *>; val root = (case["root"] as Double).toInt()
            val value = SchemaProbeJson.parse(case["input_json"] as String)
            if (!assertions.valid(root, value)) { println("REJECT"); continue }
            val canonical = SchemaProbeJson.canonical(value)
            val again = SchemaProbeJson.parse(canonical)
            require(assertions.valid(root, again) && canonical == SchemaProbeJson.canonical(again))
            println("VALID\t" + SchemaProbeJson.hex(canonical))
        } catch (_: IllegalArgumentException) { println("REJECT") }
    }
}
