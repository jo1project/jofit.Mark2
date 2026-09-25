package com.jofit.autobooking.model

import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * A recurring weekly class slot, e.g. "every Monday at 18:35, Zumba" — `courses.json` stores
 * these rather than one-off dates, because the gym's timetable repeats every week.
 */
data class CourseTemplate(
    val id: String,
    val weekday: String,
    val time: String,
    val name: String,
) {
    /**
     * Every weekday appears exactly once in any 7 consecutive days, so "the next date matching
     * this weekday, counting today" is week 0; adding multiples of 7 gives the following weeks.
     */
    fun resolvedCourses(weeksAhead: Int, today: LocalDate = LocalDate.now()): List<Course> {
        val target = WEEKDAYS.indexOf(weekday) + 1
        if (target == 0) return emptyList()
        val firstOffset = (target - today.dayOfWeek.value + 7) % 7
        return (0 until weeksAhead).map { week ->
            val date = today.plusDays((firstOffset + week * 7).toLong())
            Course("${id}_${date.format(DateTimeFormatter.BASIC_ISO_DATE)}", id, date, time, name)
        }
    }

    companion object {
        /** Used only before the first successful fetch of `courses.json` (e.g. first launch offline). */
        val fallback = listOf(
            CourseTemplate("mon-1835-1", "週一", "1835", "Zumba"),
            CourseTemplate("mon-1920-1", "週一", "1920", "基礎啞鈴"),
            CourseTemplate("mon-2035-1", "週一", "2035", "TRX"),
        )
    }
}
