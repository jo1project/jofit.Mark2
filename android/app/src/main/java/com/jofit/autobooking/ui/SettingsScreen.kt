package com.jofit.autobooking.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jofit.autobooking.data.UserSettings

@Composable
fun SettingsScreen(settings: UserSettings) {
    val t = Theme.c
    Column(Modifier.fillMaxSize().background(t.background)) {
        PageHeader("設定")
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel("個人資料")
                Column(Modifier.fillMaxWidth().cardBackground().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(settings.name, { settings.name = it }, Modifier.fillMaxWidth(), label = { Text("姓名") }, singleLine = true)
                    OutlinedTextField(settings.employeeID, { settings.employeeID = it }, Modifier.fillMaxWidth(), label = { Text("員工編號") }, singleLine = true)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel("外觀")
                Column(Modifier.fillMaxWidth().cardBackground().padding(horizontal = 16.dp)) {
                    AppTheme.entries.forEachIndexed { index, theme ->
                        if (index > 0) Hairline()
                        ChoiceRow(theme.title, settings.theme == theme) { settings.theme = theme }
                    }
                }
            }
            Text(
                "姓名與員工編號會在建立預約時傳給後端，由後端代為送出 Google 表單。預約的排程與送出都是由後端伺服器負責，跟手機有沒有開、App 有沒有被關掉無關。",
                color = t.textSecondary, fontSize = 13.sp,
            )
        }
    }
}
