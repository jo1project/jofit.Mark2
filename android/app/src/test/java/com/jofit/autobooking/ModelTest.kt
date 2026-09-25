package com.jofit.autobooking

import com.jofit.autobooking.model.CourseTemplate
import com.jofit.autobooking.model.Reservation
import java.time.LocalDate
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelTest {
    // 2026-09-25 is a Friday.
    private val friday = LocalDate.of(2026, 9, 25)

    @Test
    fun templateResolvesToNextMatchingWeekdayCountingToday() {
        val fri = CourseTemplate("fri-1", "週五", "1120", "燃脂泰拳").resolvedCourses(4, friday)
        assertEquals(listOf("2026-09-25", "2026-10-02", "2026-10-09", "2026-10-16"), fri.map { it.date.toString() })
        assertEquals("fri-1_20260925", fri[0].id)

        val mon = CourseTemplate("mon-1", "週一", "1835", "Zumba").resolvedCourses(2, friday)
        assertEquals(listOf("2026-09-28", "2026-10-05"), mon.map { it.date.toString() })
        assertEquals("9/28 週一 1835 Zumba", mon[0].submissionText)
        assertEquals("18:35", mon[0].timeText)
    }

    @Test
    fun reservationParsesBackendJsonAndRoundTrips() {
        val json = JSONObject(
            """{"id":"r1","course_id":"mon-1835-1_20260928","course_date":"2026-09-28","course_time":"1835",
            "course_name":"Zumba","submission_text":"x","reporter_name":"A","employee_id":" 123 ","status":"pending",
            "fire_date":"2026-09-22T00:00:00+00:00","submitted_at":null,"http_status":null,"last_error":null,"created_at":"x"}"""
        )
        val r = Reservation.fromJson(json)!!
        assertEquals("mon-1835-1", r.course.templateID)
        assertNull(r.submittedAt)
        assertNull(r.lastError)
        assertTrue(r.isBooked("123"))
        assertEquals(r, Reservation.fromJson(r.toJson()))

        // An unknown status (newer backend) drops the row rather than crashing the list.
        assertNull(Reservation.fromJson(JSONObject(json.toString().replace("pending", "weird"))))
    }
}
