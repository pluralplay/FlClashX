package com.follow.clashx

import android.util.Log
import androidx.lifecycle.MutableLiveData
import com.follow.clashx.plugins.AppPlugin
import com.follow.clashx.plugins.TilePlugin
import com.follow.clashx.plugins.VpnPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

enum class RunState {
    START,
    PENDING,
    STOP
}


object GlobalState {
    val runLock = ReentrantLock()

    const val NOTIFICATION_CHANNEL = "FlClashX"
    const val SUBSCRIPTION_NOTIFICATION_CHANNEL = "FlClashX_Subscription"

    const val NOTIFICATION_ID = 1
    const val SUBSCRIPTION_NOTIFICATION_ID = 2

    val runState: MutableLiveData<RunState> = MutableLiveData<RunState>(RunState.STOP)
    var flutterEngine: FlutterEngine? = null
    private var serviceEngine: FlutterEngine? = null

    fun getCurrentAppPlugin(): AppPlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(AppPlugin::class.java) as AppPlugin?
    }

    fun syncStatus() {
        CoroutineScope(Dispatchers.Default).launch {
            val status = getCurrentVPNPlugin()?.getStatus() ?: false
            withContext(Dispatchers.Main){
                runState.value = if (status) RunState.START else RunState.STOP
            }
        }
    }
    
    fun hasActiveProfile(): Boolean {
        val prefs = FlClashXApplication.getAppContext()
            .getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
        val configJson = prefs.getString("flutter.config", null)
        
        if (configJson != null) {
            try {
                val config = org.json.JSONObject(configJson)
                val currentProfileId = config.optString("currentProfileId", null)
                Log.d("GlobalState", "hasActiveProfile: currentProfileId=$currentProfileId")
                return !currentProfileId.isNullOrEmpty()
            } catch (e: Exception) {
                Log.e("GlobalState", "Error parsing config: ${e.message}")
                return false
            }
        }
        Log.d("GlobalState", "hasActiveProfile: no config found")
        return false
    }

    suspend fun getText(text: String): String {
        return getCurrentAppPlugin()?.getText(text) ?: ""
    }

    fun getCurrentTilePlugin(): TilePlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(TilePlugin::class.java) as TilePlugin?
    }

    fun getCurrentVPNPlugin(): VpnPlugin? {
        return serviceEngine?.plugins?.get(VpnPlugin::class.java) as VpnPlugin?
    }

    fun handleToggle() {
        val starting = handleStart()
        if (!starting) {
            handleStop()
        }
    }

    fun handleStart(): Boolean {
        Log.d("GlobalState", "handleStart called, current runState: ${runState.value}")
        if (runState.value == RunState.STOP) {
            Log.d("GlobalState", "Setting runState to PENDING")
            runState.value = RunState.PENDING
            runLock.withLock {
                val tilePlugin = getCurrentTilePlugin()
                Log.d("GlobalState", "TilePlugin: $tilePlugin, flutterEngine: $flutterEngine, serviceEngine: $serviceEngine")
                if (tilePlugin != null) {
                    Log.d("GlobalState", "TilePlugin exists, calling handleStart()")
                    tilePlugin.handleStart()
                } else {
                    Log.d("GlobalState", "No TilePlugin, setting pending action and calling initServiceEngine()")
                    // Set pending action BEFORE initializing service engine
                    // When Dart is ready, it will call serviceReady() which triggers the pending action
                    TilePlugin.setPendingAction(TilePlugin.Companion.PendingAction.START)
                    initServiceEngine()
                }
            }
            return true
        }
        Log.d("GlobalState", "handleStart: runState is not STOP, ignoring")
        return false
    }

    fun handleStop() {
        Log.d("GlobalState", "handleStop called, current runState: ${runState.value}")
        if (runState.value == RunState.START) {
            runState.value = RunState.PENDING
            runLock.withLock {
                val tilePlugin = getCurrentTilePlugin()
                if (tilePlugin != null) {
                    tilePlugin.handleStop()
                } else {
                    Log.d("GlobalState", "No TilePlugin for stop, setting pending action")
                    TilePlugin.setPendingAction(TilePlugin.Companion.PendingAction.STOP)
                    initServiceEngine()
                }
            }
        }
    }

    fun handleTryDestroy() {
        if (flutterEngine == null) {
            destroyServiceEngine()
        }
    }

    fun destroyServiceEngine() {
        runLock.withLock {
            serviceEngine?.destroy()
            serviceEngine = null
        }
    }

    fun initServiceEngine() {
        Log.d("GlobalState", "initServiceEngine called, serviceEngine: $serviceEngine")
        if (serviceEngine != null) {
            Log.d("GlobalState", "serviceEngine already exists, returning")
            return
        }
        destroyServiceEngine()
        runLock.withLock {
            Log.d("GlobalState", "Creating new serviceEngine")
            serviceEngine = FlutterEngine(FlClashXApplication.getAppContext())
            Log.d("GlobalState", "Registering plugins")
            io.flutter.plugins.GeneratedPluginRegistrant.registerWith(serviceEngine!!)
            serviceEngine?.plugins?.add(VpnPlugin)
            serviceEngine?.plugins?.add(AppPlugin())
            serviceEngine?.plugins?.add(TilePlugin())
            val vpnService = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "_service"
            )
            val args = if (flutterEngine == null) listOf("quick") else null
            Log.d("GlobalState", "Executing _service entrypoint with args: $args")
            serviceEngine?.dartExecutor?.executeDartEntrypoint(
                vpnService,
                args
            )
            Log.d("GlobalState", "serviceEngine initialized successfully")
        }
    }
}


