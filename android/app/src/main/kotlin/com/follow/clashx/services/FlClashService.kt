package com.follow.clashx.services

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.follow.clashx.GlobalState
import com.follow.clashx.models.VpnOptions


class FlClashXService : Service(), BaseServiceInterface {

    override fun start(options: VpnOptions) = 0

    override fun stop() {
        stopSelf()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }
    
    private var cachedBuilder: NotificationCompat.Builder? = null

    private suspend fun notificationBuilder(): NotificationCompat.Builder {
        if (cachedBuilder == null) {
            cachedBuilder = createFlClashXNotificationBuilder().await()
        }
        return cachedBuilder!!
    }

    @SuppressLint("ForegroundServiceType")
    override suspend fun startForeground(title: String, server: String?, content: String) {
        startForeground(
            notificationBuilder()
                .setContentTitle(title)
                .setContentText(content)
                .setSubText(server ?: "")
                .build()
        )
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        GlobalState.getCurrentVPNPlugin()?.requestGc()
    }


    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): FlClashXService = this@FlClashXService
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        stop()
        super.onDestroy()
    }
}