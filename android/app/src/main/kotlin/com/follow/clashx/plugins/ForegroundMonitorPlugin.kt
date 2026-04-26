package com.follow.clashx.plugins

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import com.follow.clashx.FlClashXApplication
import com.follow.clashx.GlobalState
import com.google.gson.Gson
import com.follow.clashx.models.VpnOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data object ForegroundMonitorPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var scope: CoroutineScope
    private var monitorJob: Job? = null
    private var bypassPackages = setOf<String>()
    private var wasBypassActive = false
    private var vpnOptionsJson: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(Dispatchers.Default)
        channel = MethodChannel(binding.binaryMessenger, "foreground_monitor")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        monitorJob?.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasUsageStatsPermission())
            "requestPermission" -> {
                openUsageStatsSettings()
                result.success(true)
            }
            "setBypassPackages" -> {
                @Suppress("UNCHECKED_CAST")
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                bypassPackages = packages.toSet()
                result.success(true)
            }
            "setVpnOptions" -> {
                vpnOptionsJson = call.argument<String>("options")
                result.success(true)
            }
            "startMonitor" -> {
                startMonitor()
                result.success(true)
            }
            "stopMonitor" -> {
                stopMonitor()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    fun hasUsageStatsPermission(): Boolean {
        val context = FlClashXApplication.getAppContext()
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageStatsSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        FlClashXApplication.getAppContext().startActivity(intent)
    }

    private fun getForegroundPackage(): String? {
        if (!hasUsageStatsPermission()) return null
        val context = FlClashXApplication.getAppContext()
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return null
        val end = System.currentTimeMillis()
        val begin = end - 10_000L
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, begin, end)
        return stats?.maxByOrNull { it.lastTimeUsed }?.packageName
    }

    private fun startMonitor() {
        monitorJob?.cancel()
        monitorJob = scope.launch {
            while (isActive) {
                val current = getForegroundPackage()
                val isBypassApp = current != null && bypassPackages.contains(current)

                if (isBypassApp && !wasBypassActive) {
                    wasBypassActive = true
                    withContext(Dispatchers.Main) {
                        GlobalState.getCurrentVPNPlugin()?.handleStop()
                    }
                } else if (!isBypassApp && wasBypassActive) {
                    wasBypassActive = false
                    val opts = vpnOptionsJson
                    if (opts != null) {
                        withContext(Dispatchers.Main) {
                            val options = Gson().fromJson(opts, VpnOptions::class.java)
                            GlobalState.getCurrentVPNPlugin()?.handleStart(options)
                        }
                    }
                }
                delay(1000L)
            }
        }
    }

    private fun stopMonitor() {
        monitorJob?.cancel()
        monitorJob = null
        wasBypassActive = false
    }
}
