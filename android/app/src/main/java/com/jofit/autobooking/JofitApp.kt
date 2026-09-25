package com.jofit.autobooking

import android.app.Application
import com.jofit.autobooking.data.BackendClient
import com.jofit.autobooking.data.CourseStore
import com.jofit.autobooking.data.Prefs
import com.jofit.autobooking.data.ReservationStore
import com.jofit.autobooking.data.UserSettings

/** Owns the process-wide stores (the iOS app's `@StateObject`s). */
class JofitApp : Application() {
    lateinit var settings: UserSettings
    lateinit var courseStore: CourseStore
    lateinit var reservationStore: ReservationStore

    override fun onCreate() {
        super.onCreate()
        val client = BackendClient()
        settings = UserSettings(Prefs.of(this))
        courseStore = CourseStore(this, client)
        reservationStore = ReservationStore(this, settings, client)
    }
}
