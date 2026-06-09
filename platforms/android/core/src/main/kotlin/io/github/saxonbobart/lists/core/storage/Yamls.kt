package io.github.saxonbobart.lists.core.storage

import io.github.saxonbobart.lists.core.Iso8601
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor
import java.time.Instant
import java.util.UUID

/** A frontmatter / .list.yml file that can't be decoded. Mirrors the iOS
 *  decoding errors that route a file into `.quarantine/`. */
class YamlCodecException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Shared YAML plumbing. Parsing uses SnakeYAML's safe loader; emission is
 * hand-rolled so field order and "omit defaults" rules exactly mirror the
 * iOS encoders (`Item.encode(to:)` / `ItemList.encode(to:)`).
 *
 * Note on dates: SnakeYAML resolves plain ISO scalars (as written by iOS) to
 * `java.util.Date`, so readers must accept both `String` and `Date`. On the
 * way out we double-quote date strings, which any YAML parser (including
 * Yams on iOS) reads back as plain strings.
 */
internal object Yamls {

    fun load(text: String): Map<*, *> {
        val root = try {
            Yaml(SafeConstructor(LoaderOptions())).load<Any?>(text)
        } catch (e: Exception) {
            throw YamlCodecException("Invalid YAML: ${e.message}", e)
        }
        if (root == null) throw YamlCodecException("Empty YAML document")
        return root as? Map<*, *> ?: throw YamlCodecException("YAML root is not a mapping")
    }

    // MARK: - Tolerant readers (matching the iOS decoders' strictness rules)

    fun stringOf(v: Any?): String? = when (v) {
        null -> null
        is String -> v
        is java.util.Date -> Iso8601.string(v.toInstant())
        else -> v.toString()
    }

    fun instantOf(v: Any?): Instant? = when (v) {
        is java.util.Date -> v.toInstant()
        is String -> Iso8601.instant(v)
        else -> null
    }

    fun requireString(map: Map<*, *>, key: String): String =
        stringOf(map[key]) ?: throw YamlCodecException("Missing required field '$key'")

    fun optString(map: Map<*, *>, key: String): String? = stringOf(map[key])

    /** Required ISO date — missing or invalid throws (file is quarantined). */
    fun requireInstant(map: Map<*, *>, key: String): Instant {
        val v = map[key] ?: throw YamlCodecException("Missing required field '$key'")
        return instantOf(v) ?: throw YamlCodecException("Invalid ISO 8601 date for '$key'")
    }

    /**
     * Optional ISO date — absent is fine, but present-but-invalid throws
     * (DI-3: a bad `deleted_at` silently mapped to null would resurrect a
     * deleted item; throwing routes the file to quarantine instead).
     */
    fun optInstant(map: Map<*, *>, key: String): Instant? {
        val v = map[key] ?: return null
        return instantOf(v) ?: throw YamlCodecException("Invalid ISO 8601 date for '$key'")
    }

    fun optBool(map: Map<*, *>, key: String, default: Boolean): Boolean {
        val v = map[key] ?: return default
        return v as? Boolean ?: throw YamlCodecException("Field '$key' is not a boolean")
    }

    fun optInt(map: Map<*, *>, key: String, default: Int): Int {
        val v = map[key] ?: return default
        return (v as? Number)?.toInt() ?: throw YamlCodecException("Field '$key' is not an integer")
    }

    fun optLong(map: Map<*, *>, key: String, default: Long): Long {
        val v = map[key] ?: return default
        return (v as? Number)?.toLong() ?: throw YamlCodecException("Field '$key' is not an integer")
    }

    fun optDouble(map: Map<*, *>, key: String, default: Double): Double {
        val v = map[key] ?: return default
        return (v as? Number)?.toDouble() ?: throw YamlCodecException("Field '$key' is not a number")
    }

    fun doubleOf(v: Any?): Double? = (v as? Number)?.toDouble()

    fun uuidOrThrow(raw: String, key: String): UUID = try {
        UUID.fromString(raw)
    } catch (e: IllegalArgumentException) {
        throw YamlCodecException("Invalid UUID for '$key': $raw", e)
    }

    fun uuidOrNull(raw: String?): UUID? = raw?.let {
        try {
            UUID.fromString(it)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    // MARK: - Emission

    /** Canonical uppercase UUID form, matching Swift's `UUID.uuidString`. */
    fun uuid(value: UUID): String = value.toString().uppercase()

    /** A date scalar — always double-quoted so no parser resolves it to a
     *  native timestamp type. */
    fun date(value: Instant): String = quote(Iso8601.string(value))

    private val ambiguousScalars = setOf(
        "true", "false", "yes", "no", "on", "off", "null", "~", "y", "n", "",
    )
    private val numberLike =
        Regex("^[-+]?(\\.inf|\\.nan|0x[0-9a-fA-F_]+|0o[0-7_]+|[0-9][0-9_]*\\.?[0-9_]*([eE][-+]?[0-9]+)?|\\.[0-9_]+([eE][-+]?[0-9]+)?)$")
    private val dateLike = Regex("^[0-9]{4}-[0-9]{2}.*")

    // Conservative plain-scalar shape: starts alphanumeric, then anything that
    // is never a YAML indicator in block context. Everything else gets quoted.
    private val plainSafe =
        Regex("^[A-Za-z0-9][^:#\\[\\]{}&*!|>'\"%@`\\x00-\\x1F\\x7F]*$")

    /**
     * Emit a string value as a YAML scalar: plain when unambiguously a string
     * (the common case for titles/ids, keeping files diff-friendly and close
     * to the iOS output), double-quoted otherwise.
     */
    fun scalar(value: String): String {
        val plain = plainSafe.matches(value) &&
            !value.endsWith(" ") &&
            value.lowercase() !in ambiguousScalars &&
            !numberLike.matches(value) &&
            !dateLike.matches(value)
        return if (plain) value else quote(value)
    }

    /** JSON-style double-quoted scalar with control characters escaped. */
    fun quote(value: String): String {
        val b = StringBuilder("\"")
        for (ch in value) {
            when (ch) {
                '\\' -> b.append("\\\\")
                '"' -> b.append("\\\"")
                '\n' -> b.append("\\n")
                '\r' -> b.append("\\r")
                '\t' -> b.append("\\t")
                else -> if (ch.code < 0x20 || ch.code == 0x7F) {
                    b.append("\\u").append(ch.code.toString(16).padStart(4, '0'))
                } else {
                    b.append(ch)
                }
            }
        }
        return b.append('"').toString()
    }
}
