package com.jofit.autobooking.data

import com.jofit.autobooking.model.Course
import com.jofit.autobooking.model.CourseTemplate
import com.jofit.autobooking.model.Reservation
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

sealed class BackendError(message: String) : Exception(message) {
    class InvalidResponse : BackendError("伺服器回應格式錯誤")

    class Network : BackendError("無法連線到伺服器，請檢查網路")

    class Server(val code: Int, body: String?) : BackendError(
        when (code) {
            403 -> "管理密碼錯誤"
            429 -> "密碼錯誤次數過多，請 15 分鐘後再試"
            else -> "伺服器錯誤（$code）" + (body?.let { "：$it" } ?: "")
        }
    )
}

/**
 * Talks to the VPS backend, which owns the actual "submit at the right time" job — this
 * client is just how the app creates/reads/cancels reservations.
 *
 * The URL and token are hardcoded, same as the iOS app (see `BackendClient.swift`): this repo
 * is public, so anyone who finds the token can call the backend directly with it. If that ever
 * becomes a problem, rotate BEARER_TOKEN in the VPS's `backend/.env` and update BOTH apps.
 */
class BackendClient(
    private val baseURL: String = "https://jofit.duckdns.org",
    private val token: String = "qhvg10B4b53K2kEQwqsGMHUZBr623w_Wqyz02Rnj6MU",
) {
    /** The backend only returns the caller's own reservations; with the admin [pin] it returns everyone's. */
    suspend fun listReservations(employeeID: String, pin: String? = null): List<Reservation> {
        val path = if (pin == null) "/reservations?employee_id=${encoded(employeeID)}" else "/reservations"
        return Reservation.listFromJson(send(path, pin = pin))
    }

    suspend fun createReservation(course: Course, name: String, employeeID: String): Reservation {
        val body = JSONObject()
            .put("course", JSONObject().put("id", course.id).put("date", course.date.toString())
                .put("time", course.time).put("name", course.name))
            .put("name", name)
            .put("employee_id", employeeID)
        return Reservation.fromJson(JSONObject(send("/reservations", "POST", body.toString())))
            ?: throw BackendError.InvalidResponse()
    }

    /** The backend only lets [employeeID] cancel their own reservation; the admin [pin] lifts that. */
    suspend fun cancelReservation(id: String, employeeID: String, pin: String? = null) {
        send("/reservations/$id?employee_id=${encoded(employeeID)}", "DELETE", pin = pin)
    }

    /** Admin only. Returns how many were actually cancelled — rows that started submitting meanwhile are skipped. */
    suspend fun cancelReservations(ids: List<String>, pin: String): Int {
        val body = JSONObject().put("ids", JSONArray(ids))
        return JSONObject(send("/reservations/cancel", "POST", body.toString(), pin)).optInt("cancelled")
    }

    /** Empty until an admin has saved a course list once. */
    suspend fun listCourses(): List<CourseTemplate> = CourseTemplates.parse(send("/courses"))

    /** Admin only: replaces the whole shared course list. */
    suspend fun saveCourses(templates: List<CourseTemplate>, pin: String) {
        send("/courses", "PUT", CourseTemplates.toJson(templates), pin)
    }

    private suspend fun send(path: String, method: String = "GET", body: String? = null, pin: String? = null): String =
        httpRequest(
            baseURL.trim() + path, method, body,
            mapOf("Authorization" to "Bearer $token") + (pin?.let { mapOf("X-Admin-Pin" to it) } ?: emptyMap()),
        )

    // Percent-encodes everything but letters/digits, like the iOS client; URLEncoder makes spaces "+".
    private fun encoded(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
}

/** Plain HttpURLConnection: OkHttp would buy nothing for ~6 endpoints. */
suspend fun httpRequest(
    url: String,
    method: String = "GET",
    body: String? = null,
    headers: Map<String, String> = emptyMap(),
): String = withContext(Dispatchers.IO) {
    val conn = URL(url).openConnection() as HttpURLConnection
    try {
        conn.requestMethod = method
        conn.connectTimeout = 15_000
        conn.readTimeout = 60_000
        headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
        if (body != null) {
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.outputStream.use { it.write(body.toByteArray()) }
        }
        val code = conn.responseCode
        val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
            ?.bufferedReader()?.use { it.readText() } ?: ""
        if (code !in 200..299) throw BackendError.Server(code, text.ifEmpty { null })
        text
    } catch (e: IOException) {
        throw BackendError.Network()
    } finally {
        conn.disconnect()
    }
}

object CourseTemplates {
    fun parse(text: String): List<CourseTemplate> {
        val array = JSONArray(text)
        return (0 until array.length()).map {
            val o = array.getJSONObject(it)
            CourseTemplate(o.getString("id"), o.getString("weekday"), o.getString("time"), o.getString("name"))
        }
    }

    fun toJson(templates: List<CourseTemplate>): String = JSONArray(templates.map {
        JSONObject().put("id", it.id).put("weekday", it.weekday).put("time", it.time).put("name", it.name)
    }).toString()
}
