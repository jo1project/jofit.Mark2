package com.jofit.autobooking.model

import java.time.LocalDate

/** Monday-first, matching `java.time.DayOfWeek.value - 1`. */
val WEEKDAYS = listOf("週一", "週二", "週三", "週四", "週五", "週六", "週日")

/**
 * A concrete, bookable instance of a class on a specific calendar date — resolved from a
 * [CourseTemplate] (a weekly-recurring slot) for one particular week.
 */
data class Course(
    val id: String,
    /** The [CourseTemplate.id] this instance was resolved from, so the UI can group every week's occurrence. */
    val templateID: String,
    val date: LocalDate,
    val time: String,
    val name: String,
) {
    val weekdayLabel: String get() = WEEKDAYS[date.dayOfWeek.value - 1]

    val dateText: String get() = "%d/%02d".format(date.monthValue, date.dayOfMonth)

    val timeText: String get() = displayTime(time)

    /** Must match the format the Jofit admin parses by hand, e.g. "1/16 週六 1120 燃脂泰拳". */
    val submissionText: String get() = "$dateText $weekdayLabel $time $name"

    companion object {
        /** Display-only "1920" -> "19:20". `submissionText` keeps the raw form the admin parses. */
        fun displayTime(raw: String): String = if (raw.length == 4) "${raw.take(2)}:${raw.takeLast(2)}" else raw
    }
}
