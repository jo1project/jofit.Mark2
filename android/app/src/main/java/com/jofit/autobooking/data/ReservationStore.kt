package com.jofit.autobooking.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.glance.appwidget.updateAll
import com.jofit.autobooking.model.Course
import com.jofit.autobooking.model.Reservation
import com.jofit.autobooking.widget.JofitWidget
import java.io.File
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONArray

/**
 * The client-side view of reservations. All the actual scheduling — deciding when to submit
 * and doing it — happens on the VPS backend (see [BackendClient]), so this store is a thin
 * sync layer: it mirrors the backend's state, caches the last-known state on disk for offline
 * display, and keeps the home screen widget up to date.
 */
class ReservationStore(
    private val context: Context,
    private val settings: UserSettings,
    private val client: BackendClient,
) {
    var reservations by mutableStateOf(emptyList<Reservation>())
        private set
    var isSyncing by mutableStateOf(false)
        private set
    var lastSyncError by mutableStateOf<String?>(null)

    /**
     * True once the admin PIN has been accepted this session; from then on [reservations] holds
     * everyone's (the backend otherwise only returns the caller's own).
     */
    var isAdminUnlocked by mutableStateOf(false)
        private set

    private var adminPIN: String? = null

    /**
     * Every backend call is scoped to this: the backend has no login, it trusts the caller to
     * name themselves and only hands back / lets them cancel that person's reservations.
     */
    private val employeeID: String get() = settings.employeeID.trim()

    init {
        reservations = loadCache(context)
    }

    /** One reservation per person per class: other students' reservations for the same class don't count. */
    fun reservation(courseID: String, employeeID: String): Reservation? =
        reservations.firstOrNull { it.course.id == courseID && it.isBooked(employeeID) }

    suspend fun refresh() = detached {
        if (adminPIN == null && employeeID.isEmpty()) return@detached
        isSyncing = true
        try {
            reservations = client.listReservations(employeeID, adminPIN)
            lastSyncError = null
            saveCache()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (e is BackendError.Server && e.code == 403) lockAdmin()
            lastSyncError = e.message
        } finally {
            isSyncing = false
        }
    }

    /**
     * Throws (wrong PIN, network) so the caller can show it. On success the PIN is kept in
     * memory only, so refreshes keep returning everyone's reservations until the app quits.
     */
    suspend fun unlockAdmin(pin: String) = detached {
        reservations = client.listReservations(employeeID, pin)
        adminPIN = pin
        isAdminUnlocked = true
        lastSyncError = null
        saveCache()
    }

    private fun lockAdmin() {
        adminPIN = null
        isAdminUnlocked = false
    }

    suspend fun reserve(course: Course, name: String, employeeID: String): Reservation? = detached {
        try {
            client.createReservation(course, name, employeeID).also {
                upsert(it)
                lastSyncError = null
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            lastSyncError = e.message
            null
        }
    }

    suspend fun cancel(reservation: Reservation) = detached {
        try {
            client.cancelReservation(reservation.id, employeeID, adminPIN)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // 404: already gone, or sent in the meantime (a lost DELETE response lands here
            // too); the refresh below shows which.
            if (!(e is BackendError.Server && e.code == 404)) {
                lastSyncError = e.message
                return@detached
            }
        }
        // Confirm against the backend's list rather than trusting our own removal.
        refresh()
        if (lastSyncError == null && reservations.any { it.id == reservation.id }) {
            lastSyncError = "這筆預約已無法取消"
        }
    }

    /**
     * Admin bulk cancel of pending reservations; throws (wrong PIN, network) so the caller can
     * show it. Returns how many were really cancelled — may be fewer than asked if some fired
     * in the meantime.
     */
    suspend fun cancelPending(targets: List<Reservation>, pin: String): Int = detached {
        client.cancelReservations(targets.map { it.id }, pin).also { refresh() }
    }

    private fun upsert(reservation: Reservation) {
        reservations = if (reservations.any { it.id == reservation.id }) {
            reservations.map { if (it.id == reservation.id) reservation else it }
        } else {
            reservations + reservation
        }
        saveCache()
    }

    private fun refreshWidget() {
        AppScope.scope.launch { JofitWidget().updateAll(context) }
    }

    private fun saveCache() {
        refreshWidget()
        runCatching { cacheFile(context).writeText(JSONArray(reservations.map { it.toJson() }).toString()) }
    }

    companion object {
        private fun cacheFile(context: Context) = File(context.filesDir, "reservations_cache.json")

        private fun loadCache(context: Context): List<Reservation> =
            runCatching { Reservation.listFromJson(cacheFile(context).readText()) }.getOrDefault(emptyList())

        /** For the widget: this user's own submitted courses on [day] (the cache holds everyone's for an admin). */
        fun myCoursesOn(context: Context, day: LocalDate): List<Course> {
            val mine = Prefs.of(context).getString(Prefs.EMPLOYEE_ID, "") ?: ""
            return loadCache(context)
                .filter { it.status == Reservation.Status.Submitted && it.isBooked(mine) && it.course.date == day }
                .map { it.course }
                .sortedBy { it.time }
        }
    }
}
