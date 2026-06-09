package io.github.saxonbobart.lists.core.model

/** The reminder block, shared by tasks and habits. */
data class Reminder(
    val enabled: Boolean,
    val early: EarlyReminder? = null,
)

/** Optional "remind me X before due" offset. */
data class EarlyReminder(
    val value: Int,
    val unit: Unit,
) {
    enum class Unit(val raw: String) {
        MINUTE("minute"), HOUR("hour"), DAY("day"), WEEK("week"), MONTH("month");

        companion object {
            fun fromRawOrNull(raw: String): Unit? = entries.firstOrNull { it.raw == raw }
        }
    }
}

/** Triggers — universal data, device-restricted firing. */
data class Triggers(
    val urgent: TriggerToggle? = null,
    val location: LocationTrigger? = null,
)

data class TriggerToggle(val enabled: Boolean)

data class LocationTrigger(
    val enabled: Boolean,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val radius: Double? = null,
    val fire: Direction? = null,
) {
    enum class Direction(val raw: String) {
        ARRIVE("arrive"), LEAVE("leave");

        companion object {
            fun fromRawOrNull(raw: String): Direction? = entries.firstOrNull { it.raw == raw }
        }
    }
}

/** RFC 5545 RRULE wrapper; the string is opaque at this layer. */
data class Recurrence(val rrule: String)

/**
 * Habit cadence. The full set exists because old data may reference it, but a
 * habit is locked to daily / weekly / monthly; anything else folds onto one of
 * the three via [normalizedForHabit].
 */
enum class HabitFrequency(val raw: String) {
    HOURLY("hourly"),
    DAILY("daily"),
    WEEKDAYS("weekdays"),
    WEEKENDS("weekends"),
    WEEKLY("weekly"),
    FORTNIGHTLY("fortnightly"),
    MONTHLY("monthly"),
    EVERY_THREE_MONTHS("every_three_months"),
    EVERY_SIX_MONTHS("every_six_months"),
    YEARLY("yearly"),
    CUSTOM("custom");

    val normalizedForHabit: HabitFrequency
        get() = when (this) {
            DAILY, HOURLY, WEEKDAYS, WEEKENDS, CUSTOM -> DAILY
            WEEKLY, FORTNIGHTLY -> WEEKLY
            MONTHLY, EVERY_THREE_MONTHS, EVERY_SIX_MONTHS, YEARLY -> MONTHLY
        }

    companion object {
        /** The only cadences a habit may be set to. */
        val habitCadences: List<HabitFrequency> = listOf(DAILY, WEEKLY, MONTHLY)

        fun fromRawOrNull(raw: String): HabitFrequency? = entries.firstOrNull { it.raw == raw }
    }
}
