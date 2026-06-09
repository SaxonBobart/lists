package io.github.saxonbobart.lists.core.storage

import io.github.saxonbobart.lists.core.model.Item

/**
 * Encode/decode an [Item] to/from a markdown file with YAML frontmatter —
 * the same on-disk layout the iOS app reads and writes:
 *
 * ```
 * ---
 * id: 01HX...
 * type: task
 * title: Pay phone bill
 * ...
 * ---
 * <markdown body>
 * ```
 */
object FrontmatterCodec {

    fun encode(item: Item): String {
        val yaml = ItemYaml.encode(item) // always newline-terminated
        val body = when {
            item.body.isEmpty() -> ""
            item.body.endsWith("\n") -> item.body
            else -> item.body + "\n"
        }
        return "---\n$yaml---\n$body"
    }

    fun decode(source: String): Item {
        val (frontmatter, body) = splitFrontmatter(source)
        return ItemYaml.decode(frontmatter).copy(body = body)
    }

    private fun splitFrontmatter(source: String): Pair<String, String> {
        // Accept files starting with "---\n" or BOM + "---\n"
        val stripped = source.removePrefix("\uFEFF")
        if (!stripped.startsWith("---\n")) throw YamlCodecException("Missing frontmatter opener")
        val after = stripped.substring(4)
        val close = after.indexOf("\n---\n")
        if (close < 0) {
            // Allow file ending right at "\n---" (no trailing newline + body)
            if (after.endsWith("\n---")) {
                return after.substring(0, after.length - 4) to ""
            }
            throw YamlCodecException("Missing frontmatter closer")
        }
        return after.substring(0, close) to after.substring(close + 5)
    }
}
