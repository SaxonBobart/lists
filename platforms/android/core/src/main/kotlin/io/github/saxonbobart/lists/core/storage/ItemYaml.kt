package io.github.saxonbobart.lists.core.storage

import io.github.saxonbobart.lists.core.model.EarlyReminder
import io.github.saxonbobart.lists.core.model.HabitCompletion
import io.github.saxonbobart.lists.core.model.HabitFrequency
import io.github.saxonbobart.lists.core.model.Item
import io.github.saxonbobart.lists.core.model.ItemType
import io.github.saxonbobart.lists.core.model.LocationTrigger
import io.github.saxonbobart.lists.core.model.Priority
import io.github.saxonbobart.lists.core.model.Recurrence
import io.github.saxonbobart.lists.core.model.Reminder
import io.github.saxonbobart.lists.core.model.TriggerToggle
import io.github.saxonbobart.lists.core.model.Triggers
import java.util.UUID

/**
 * Item <-> YAML frontmatter mapping. Field order, key names, and
 * omit-when-default rules mirror `Item` Codable on iOS exactly, so both
 * platforms read and write the same files.
 */
internal object ItemYaml {

    fun encode(item: Item): String {
        val b = StringBuilder()
        fun line(key: String, value: String) = b.append(key).append(": ").append(value).append('\n')

        line("id", Yamls.uuid(item.id))
        line("type", item.type.raw)
        line("title", Yamls.scalar(item.title))
        line("list", Yamls.scalar(item.listId))
        item.section?.let { line("section", Yamls.scalar(it)) }
        item.parentId?.let { line("parent", Yamls.uuid(it)) }
        if (item.tags.isNotEmpty()) {
            b.append("tags:\n")
            for (tag in item.tags) b.append("- ").append(Yamls.scalar(tag)).append('\n')
        }
        line("created_at", Yamls.date(item.createdAt))
        line("modified_at", Yamls.date(item.modifiedAt))
        line("created_by", Yamls.scalar(item.createdBy))
        if (item.done) line("done", "true")
        item.completedAt?.let { line("completed_at", Yamls.date(it)) }
        item.due?.let { line("due", Yamls.date(it)) }
        if (item.dueAllDay) line("due_all_day", "true")
        item.dueTimeZone?.let { line("due_timezone", Yamls.scalar(it)) }
        if (item.priority != Priority.NONE) line("priority", item.priority.raw)
        if (item.flagged) line("flagged", "true")
        item.reminder?.let { r ->
            b.append("reminder:\n")
            b.append("  enabled: ").append(r.enabled).append('\n')
            r.early?.let { e ->
                b.append("  early:\n")
                b.append("    value: ").append(e.value).append('\n')
                b.append("    unit: ").append(e.unit.raw).append('\n')
            }
        }
        item.recurrence?.let { rec ->
            b.append("recurrence:\n")
            b.append("  rrule: ").append(Yamls.scalar(rec.rrule)).append('\n')
        }
        item.triggers?.let { t ->
            b.append("triggers:\n")
            t.urgent?.let { u ->
                b.append("  urgent:\n")
                b.append("    enabled: ").append(u.enabled).append('\n')
            }
            t.location?.let { l ->
                b.append("  location:\n")
                b.append("    enabled: ").append(l.enabled).append('\n')
                l.latitude?.let { b.append("    latitude: ").append(it).append('\n') }
                l.longitude?.let { b.append("    longitude: ").append(it).append('\n') }
                l.radius?.let { b.append("    radius: ").append(it).append('\n') }
                l.fire?.let { b.append("    fire: ").append(it.raw).append('\n') }
            }
        }
        if (item.type == ItemType.HABIT) {
            item.frequency?.let { line("frequency", it.raw) }
            line("goal_per_cycle", item.goalPerCycle.toString())
            if (item.completions.isNotEmpty()) {
                b.append("completions:\n")
                for (c in item.completions) {
                    b.append("- id: ").append(Yamls.uuid(c.id)).append('\n')
                    b.append("  at: ").append(Yamls.date(c.at)).append('\n')
                }
            }
            line("show_streak", item.showStreak.toString())
            if (item.flexibleGoal) line("flexible_goal", "true")
        }
        item.deletedAt?.let { line("deleted_at", Yamls.date(it)) }
        if (item.sortIndex != 0) line("sort_index", item.sortIndex.toString())
        return b.toString()
    }

    fun decode(frontmatter: String): Item {
        val map = Yamls.load(frontmatter)

        val type = ItemType.fromRaw(Yamls.requireString(map, "type"))
        val frequency = Yamls.optString(map, "frequency")?.let {
            HabitFrequency.fromRawOrNull(it)
                ?: throw YamlCodecException("Unknown frequency '$it'")
        }

        return Item(
            id = Yamls.uuidOrThrow(Yamls.requireString(map, "id"), "id"),
            type = type,
            title = Yamls.requireString(map, "title"),
            body = "", // populated by FrontmatterCodec
            listId = Yamls.requireString(map, "list"),
            section = Yamls.optString(map, "section"),
            parentId = Yamls.optString(map, "parent")?.let { Yamls.uuidOrThrow(it, "parent") },
            tags = decodeTags(map),
            createdAt = Yamls.requireInstant(map, "created_at"),
            modifiedAt = Yamls.requireInstant(map, "modified_at"),
            createdBy = Yamls.optString(map, "created_by") ?: "human",
            done = Yamls.optBool(map, "done", false),
            completedAt = Yamls.optInstant(map, "completed_at"),
            due = Yamls.optInstant(map, "due"),
            dueAllDay = Yamls.optBool(map, "due_all_day", false),
            dueTimeZone = Yamls.optString(map, "due_timezone"),
            priority = Yamls.optString(map, "priority")?.let {
                Priority.fromRawOrNull(it) ?: throw YamlCodecException("Unknown priority '$it'")
            } ?: Priority.NONE,
            flagged = Yamls.optBool(map, "flagged", false),
            reminder = decodeReminder(map["reminder"]),
            recurrence = decodeRecurrence(map["recurrence"]),
            triggers = decodeTriggers(map["triggers"]),
            frequency = frequency,
            goalPerCycle = Yamls.optInt(map, "goal_per_cycle", 1),
            completions = decodeCompletions(map, frequency),
            showStreak = Yamls.optBool(map, "show_streak", true),
            flexibleGoal = Yamls.optBool(map, "flexible_goal", false),
            deletedAt = Yamls.optInstant(map, "deleted_at"),
            sortIndex = Yamls.optInt(map, "sort_index", 0),
        )
    }

    private fun decodeTags(map: Map<*, *>): List<String> {
        val v = map["tags"] ?: return emptyList()
        val list = v as? List<*> ?: throw YamlCodecException("'tags' is not a list")
        return list.map { Yamls.stringOf(it) ?: throw YamlCodecException("Invalid tag value") }
    }

    /**
     * New shape: timestamped events, decoded lossily — a single malformed
     * event is skipped rather than aborting the whole habit. Falls back to a
     * one-way migration of the legacy `completion_log` count dictionary.
     */
    private fun decodeCompletions(map: Map<*, *>, frequency: HabitFrequency?): List<HabitCompletion> {
        when (val raw = map["completions"]) {
            null -> {}
            is List<*> -> return raw.mapNotNull { decodeCompletion(it) }
            else -> throw YamlCodecException("'completions' is not a list")
        }
        when (val legacy = map["completion_log"]) {
            null -> {}
            is Map<*, *> -> {
                val log = legacy.entries.associate { (k, v) ->
                    // Daily cycle keys ("2026-05-08") resolve to Dates in YAML;
                    // fold them back to the day-string form the log uses.
                    val key = when (k) {
                        is java.util.Date -> io.github.saxonbobart.lists.core.Iso8601.dayString(k.toInstant())
                        else -> Yamls.stringOf(k) ?: throw YamlCodecException("Invalid completion_log key")
                    }
                    val count = (v as? Number)?.toInt()
                        ?: throw YamlCodecException("Invalid completion_log count")
                    key to count
                }
                return HabitCompletion.migrate(log, frequency ?: HabitFrequency.DAILY)
            }
            else -> throw YamlCodecException("'completion_log' is not a mapping")
        }
        return emptyList()
    }

    private fun decodeCompletion(el: Any?): HabitCompletion? {
        val m = el as? Map<*, *> ?: return null
        val at = Yamls.instantOf(m["at"]) ?: return null
        val id = when (val rawId = m["id"]) {
            null -> UUID.randomUUID() // tolerated: synthesize, hand-edited files still load
            else -> Yamls.uuidOrNull(Yamls.stringOf(rawId)) ?: return null
        }
        return HabitCompletion(id, at)
    }

    private fun decodeReminder(v: Any?): Reminder? {
        val m = v as? Map<*, *> ?: return v?.let {
            throw YamlCodecException("'reminder' is not a mapping")
        }
        val enabled = m["enabled"] as? Boolean
            ?: throw YamlCodecException("reminder.enabled missing or not a boolean")
        val early = (m["early"] as? Map<*, *>)?.let { e ->
            val value = (e["value"] as? Number)?.toInt()
                ?: throw YamlCodecException("reminder.early.value missing or not an integer")
            val unitRaw = Yamls.stringOf(e["unit"])
                ?: throw YamlCodecException("reminder.early.unit missing")
            val unit = EarlyReminder.Unit.fromRawOrNull(unitRaw)
                ?: throw YamlCodecException("Unknown reminder unit '$unitRaw'")
            EarlyReminder(value, unit)
        }
        return Reminder(enabled, early)
    }

    private fun decodeRecurrence(v: Any?): Recurrence? {
        val m = v as? Map<*, *> ?: return v?.let {
            throw YamlCodecException("'recurrence' is not a mapping")
        }
        val rrule = Yamls.stringOf(m["rrule"])
            ?: throw YamlCodecException("recurrence.rrule missing")
        return Recurrence(rrule)
    }

    private fun decodeTriggers(v: Any?): Triggers? {
        val m = v as? Map<*, *> ?: return v?.let {
            throw YamlCodecException("'triggers' is not a mapping")
        }
        val urgent = (m["urgent"] as? Map<*, *>)?.let { u ->
            TriggerToggle(
                u["enabled"] as? Boolean
                    ?: throw YamlCodecException("triggers.urgent.enabled missing or not a boolean"),
            )
        }
        val location = (m["location"] as? Map<*, *>)?.let { l ->
            LocationTrigger(
                enabled = l["enabled"] as? Boolean
                    ?: throw YamlCodecException("triggers.location.enabled missing or not a boolean"),
                latitude = Yamls.doubleOf(l["latitude"]),
                longitude = Yamls.doubleOf(l["longitude"]),
                radius = Yamls.doubleOf(l["radius"]),
                fire = Yamls.stringOf(l["fire"])?.let {
                    LocationTrigger.Direction.fromRawOrNull(it)
                        ?: throw YamlCodecException("Unknown trigger direction '$it'")
                },
            )
        }
        return Triggers(urgent, location)
    }
}
