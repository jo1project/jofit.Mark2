package com.jofit.autobooking.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async

/** Lives as long as the process; stores run their network work here so a screen leaving composition can't cancel it. */
object AppScope {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
}

/** Runs [block] in [AppScope] and waits for it; cancelling the caller doesn't cancel the block. */
suspend fun <T> detached(block: suspend () -> T): T = AppScope.scope.async { block() }.await()
