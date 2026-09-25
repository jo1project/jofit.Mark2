package com.jofit.autobooking.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jofit.autobooking.ui.AppTheme
import kotlin.reflect.KProperty

object Prefs {
    const val NAME = "settings.name"
    const val EMPLOYEE_ID = "settings.employeeID"
    const val HAS_ONBOARDED = "settings.hasOnboarded"
    const val THEME = "settings.theme"

    /** Also read by the widget, which shares this process but not the stores. */
    fun of(context: Context): SharedPreferences = context.getSharedPreferences("jofit", Context.MODE_PRIVATE)
}

/** Observable state that writes itself to disk on every set. */
private class Persisted<T>(initial: T, private val save: (T) -> Unit) {
    private var value by mutableStateOf(initial)
    operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value
    operator fun setValue(thisRef: Any?, property: KProperty<*>, new: T) {
        value = new
        save(new)
    }
}

class UserSettings(private val prefs: SharedPreferences) {
    var name by Persisted(prefs.getString(Prefs.NAME, "") ?: "") { prefs.edit().putString(Prefs.NAME, it).apply() }
    var employeeID by Persisted(prefs.getString(Prefs.EMPLOYEE_ID, "") ?: "") {
        prefs.edit().putString(Prefs.EMPLOYEE_ID, it).apply()
    }

    /**
     * Set once the user completes the first-launch onboarding screen. Kept separate from
     * [isComplete] so clearing a field later in Settings doesn't re-trigger the onboarding gate.
     */
    var hasOnboarded by Persisted(prefs.getBoolean(Prefs.HAS_ONBOARDED, false)) {
        prefs.edit().putBoolean(Prefs.HAS_ONBOARDED, it).apply()
    }

    var theme by Persisted(AppTheme.from(prefs.getString(Prefs.THEME, null))) {
        prefs.edit().putString(Prefs.THEME, it.name).apply()
    }

    /**
     * Soft gate only (the name is just typed into Settings): it decides which screens show. The
     * real protection is the admin PIN the backend checks on every admin action.
     */
    val isAdmin: Boolean get() = name.trim() == "林晏瑜"

    val isComplete: Boolean get() = name.isNotBlank() && employeeID.isNotBlank()
}
