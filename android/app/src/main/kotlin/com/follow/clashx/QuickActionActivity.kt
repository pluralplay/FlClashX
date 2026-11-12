package com.follow.clashx

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.core.content.pm.ShortcutManagerCompat
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.QuickAction
import com.follow.clashx.common.action
import com.follow.clashx.common.shortcutId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class QuickActionActivity : Activity() {
    private var actionsInFlight = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12 passes touches through another app's window only if it is fully transparent.
        window.attributes = window.attributes.apply { alpha = 0f }
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
        handle(intent)
    }

    // A caller that repeats an action before this instance is gone reaches it here, not onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent) {
        val action = QuickAction.entries.firstOrNull { it.action == intent.action }
        if (action == null) {
            finishIfIdle()
            return
        }
        ShortcutManagerCompat.reportShortcutUsed(this, action.shortcutId)
        actionsInFlight++
        GlobalState.launch {
            try {
                when (action) {
                    QuickAction.START -> ServiceState.handleStartAction()
                    QuickAction.STOP -> ServiceState.handleStopAction()
                    QuickAction.TOGGLE -> ServiceState.handleToggleAction()
                }
                holdUntilStarted()
            } finally {
                withContext(Dispatchers.Main) {
                    actionsInFlight--
                    finishIfIdle()
                }
            }
        }
    }

    // A service goes foreground only while its app is or just was visible; Core setup outlasts it.
    private suspend fun holdUntilStarted() {
        withTimeoutOrNull(START_HOLD_MILLIS) {
            while (ServiceState.isRunRequested && ServiceState.runState.value != RunState.STARTED) {
                delay(START_POLL_MILLIS)
            }
        }
    }

    private fun finishIfIdle() {
        if (actionsInFlight == 0 && !isFinishing) {
            finish()
        }
    }

    private companion object {
        const val START_HOLD_MILLIS = 30_000L
        const val START_POLL_MILLIS = 100L
    }
}
