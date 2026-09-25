package com.jofit.autobooking.model

import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import org.json.JSONArray
import org.json.JSONObject

/**
 * A user's intent to book a specific [Course]. The VPS backend owns the actual lifecycle
 * (deciding when to submit and doing it); this is just the client's view of that state.
 * The JSON form is the backend's wire format, which is also what the on-disk cache stores.
 */
data class Reservation(
    val id: String,
    val course: Course,
    val status: Status,
    val fireDate: Instant,
    val submittedAt: Instant?,
    val httpStatus: Int?,
    val lastError: String?,
    /** Who booked it — the backend keeps every user's reservations in one table. */
    val reporterName: String?,
    val employeeID: String?,
) {
    enum class Status(val wire: String) { Pending("pending"), Submitting("submitting"), Submitted("submitted"), Failed("failed") }

    fun isBooked(by: String): Boolean {
        val mine = by.trim()
        return mine.isNotEmpty() && (employeeID ?: "").trim() == mine
    }

    /**
     * Cancellable only while still waiting for a future fire time (courses under 6 days out
     * are sent immediately, so they never wait). A failed one can be cleared to book again.
     * Submitting/submitted can't be recalled — Google Forms has no undo.
     */
    val canDismiss: Boolean
        get() = (status == Status.Pending && fireDate.isAfter(Instant.now())) || status == Status.Failed

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("course_id", course.id)
        .put("course_date", course.date.toString())
        .put("course_time", course.time)
        .put("course_name", course.name)
        .put("status", status.wire)
        .put("fire_date", fireDate.toString())
        .put("submitted_at", submittedAt?.toString() ?: JSONObject.NULL)
        .put("http_status", httpStatus ?: JSONObject.NULL)
        .put("last_error", lastError ?: JSONObject.NULL)
        .put("reporter_name", reporterName ?: JSONObject.NULL)
        .put("employee_id", employeeID ?: JSONObject.NULL)

    companion object {
        /** Null if the row is malformed or has a status this version doesn't know. */
        fun fromJson(o: JSONObject): Reservation? = runCatching {
            val status = Status.entries.first { it.wire == o.getString("status") }
            val courseID = o.getString("course_id")
            // courseID is "<templateID>_<yyyyMMdd>" — strip the stamp back off. Only used for
            // display grouping, so falling back to the whole id if it doesn't match is harmless.
            val templateID = courseID.replace(Regex("_[0-9]{8}$"), "")
            Reservation(
                id = o.getString("id"),
                course = Course(
                    courseID, templateID, LocalDate.parse(o.getString("course_date")),
                    o.getString("course_time"), o.getString("course_name"),
                ),
                status = status,
                fireDate = OffsetDateTime.parse(o.getString("fire_date")).toInstant(),
                submittedAt = o.str("submitted_at")?.let { OffsetDateTime.parse(it).toInstant() },
                httpStatus = if (o.isNull("http_status")) null else o.getInt("http_status"),
                lastError = o.str("last_error"),
                reporterName = o.str("reporter_name"),
                employeeID = o.str("employee_id"),
            )
        }.getOrNull()

        fun listFromJson(text: String): List<Reservation> {
            val array = JSONArray(text)
            return (0 until array.length()).mapNotNull { fromJson(array.getJSONObject(it)) }
        }
    }
}

/** Android's `optString` turns a JSON null into the string "null"; this returns a real null. */
fun JSONObject.str(name: String): String? = if (isNull(name)) null else getString(name)
