package com.jofit.autobooking

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.jofit.autobooking.ui.JofitTheme
import com.jofit.autobooking.ui.MainScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as JofitApp
        setContent {
            JofitTheme(app.settings.theme) {
                MainScreen(app.settings, app.courseStore, app.reservationStore)
            }
        }
    }
}
