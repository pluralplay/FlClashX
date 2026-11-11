package com.follow.clashx

import android.app.Activity
import android.os.Build
import android.view.Display

/** Keeps the window on the fastest display mode while the activity is in front. */
class HighRefreshRate(private val activity: Activity) {
    fun pin() {
        val display = currentDisplay() ?: return
        val info = { mode: Display.Mode ->
            DisplayModeInfo(mode.modeId, mode.physicalWidth, mode.physicalHeight, mode.refreshRate)
        }
        val id = runCatching {
            fastestModeId(info(display.mode), display.supportedModes.map(info))
        }.getOrNull() ?: return
        apply(id)
    }

    fun release() = apply(0)

    private fun currentDisplay(): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
    }

    private fun apply(id: Int) {
        val window = activity.window ?: return
        val attrs = window.attributes
        if (attrs.preferredDisplayModeId == id) return
        attrs.preferredDisplayModeId = id
        window.attributes = attrs
    }
}
