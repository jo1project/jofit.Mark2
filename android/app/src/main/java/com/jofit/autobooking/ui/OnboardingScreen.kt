package com.jofit.autobooking.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jofit.autobooking.data.UserSettings

/** First-launch gate: name and employee ID are required before the app can be used. */
@Composable
fun OnboardingScreen(settings: UserSettings) {
    val t = Theme.c
    Column(
        Modifier.fillMaxSize().background(t.background).systemBarsPadding().imePadding().padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
    ) {
        Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, Modifier.size(64.dp), tint = t.brand)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("歡迎使用 Jofit 自動報名", color = t.ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text(
                "第一次使用請先填寫姓名與員工編號，之後每次報名都會自動帶入這份資料。",
                color = t.textSecondary, fontSize = 14.sp, textAlign = TextAlign.Center,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(settings.name, { settings.name = it }, Modifier.fillMaxWidth(), label = { Text("姓名") }, singleLine = true)
            OutlinedTextField(
                settings.employeeID, { settings.employeeID = it }, Modifier.fillMaxWidth(), label = { Text("員工編號") },
                singleLine = true,
            )
        }
        Spacer(Modifier.size(8.dp))
        PrimaryButton({ settings.hasOnboarded = true }, Modifier.fillMaxWidth(), enabled = settings.isComplete) { ButtonLabel("開始使用") }
    }
}
