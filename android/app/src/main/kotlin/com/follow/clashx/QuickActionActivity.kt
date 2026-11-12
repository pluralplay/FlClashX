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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class QuickActionActivity : Activity() {
    private var hold: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12 passes touches through another app's window only if it is fully transparent.
        window.attributes = window.attributes.apply { alpha = 0f }
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
        // A recreated instance gets the same intent again; a second dispatch turns a TOGGLE back.
        if (savedInstanceState == null) {
            handle(intent)
        }
        holdUntilStarted()
    }

    // A caller that repeats an action before this instance is gone reaches it here, not onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) {
            finish()
        }
    }

    override fun onDestroy() {
        hold?.cancel()
        super.onDestroy()
    }

    private fun handle(intent: Intent) {
        val action = QuickAction.entries.firstOrNull { it.action == intent.action } ?: return
        ShortcutManagerCompat.reportShortcutUsed(this, action.shortcutId)
        mainThreadActionsInFlight++
        GlobalState.launch {
            try {
                when (action) {
                    QuickAction.START -> ServiceState.handleStartAction()
                    QuickAction.STOP -> ServiceState.handleStopAction()
                    QuickAction.TOGGLE -> ServiceState.handleToggleAction()
                }
            } finally {
                withContext(Dispatchers.Main) { mainThreadActionsInFlight-- }
            }
        }
    }

    // A service goes foreground only while its app is or just was visible; Core setup outlasts it.
    private fun holdUntilStarted() {
        hold?.cancel()
        hold = GlobalState.launch(Dispatchers.Main) {
            while (mainThreadActionsInFlight > 0 || isStartPending()) {
                delay(HOLD_POLL_MILLIS)
            }
            finish()
        }
    }

    private fun isStartPending(): Boolean =
        ServiceState.isRunRequested && ServiceState.runState.value != RunState.STARTED

    private companion object {
        const val HOLD_POLL_MILLIS = 100L

        var mainThreadActionsInFlight = 0
    }
}
