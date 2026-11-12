package com.follow.clashx

import android.Manifest
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.follow.clashx.common.GlobalState
import com.follow.clashx.models.SharedState
import com.follow.clashx.plugins.AppPlugin
import com.follow.clashx.plugins.ServicePlugin
import com.follow.clashx.plugins.TilePlugin
import com.follow.clashx.service.ServiceConfig
import com.follow.clashx.service.models.NotificationParams
import com.follow.clashx.service.models.VpnOptions
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CoroutineScope

internal data class ServiceRuntime(
    val vpn: Boolean,
    val startedAtMillis: Long,
)

/**
 * The machine owns the arbitration and the transitions; this is only the part that cannot run on a
 * plain JVM, so unit tests can drive the state machine with an in-memory implementation.
 */
internal interface ServiceStateHost {
    val scope: CoroutineScope
    val runtime: ServiceRuntime?
    val homeDirPath: String
    val sdkInt: Int

    fun log(message: String)

    fun showToast(message: String)

    fun updateNotificationParams(params: NotificationParams)

    fun loadSharedState(): SharedState

    fun isVpnPermissionGranted(): Boolean

    fun isLocalNetworkPermissionGranted(): Boolean

    fun tile(): TileGateway?

    fun app(): AppGateway?

    fun notifyStopped()

    fun notifyStopRequested()

    suspend fun quickSetup(initParams: String, setupParams: String): Result<String>

    suspend fun startService(options: VpnOptions): Boolean

    suspend fun stopService()
}

internal fun interface TileGateway {
    fun handleStart(onAnswered: () -> Unit)
}

internal interface AppGateway {
    fun requestNotificationPermission(callback: (Boolean) -> Unit)

    fun requestLocalNetworkPermission(callback: (Boolean) -> Unit)

    /** [isCurrent] is asked again on the main thread, right before the consent opens. */
    fun prepareVpn(enable: Boolean, isCurrent: () -> Boolean, callback: (Boolean) -> Unit)

    fun cancelVpnPreparation(callback: (Boolean) -> Unit)

    /** Says why the start was refused, unless [isCurrent] no longer holds by then. */
    fun explainVpnRefusal(isCurrent: () -> Boolean)
}

internal object AndroidServiceStateHost : ServiceStateHost {
    @Volatile
    private var flutterEngine: FlutterEngine? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override val scope: CoroutineScope
        get() = GlobalState

    override val runtime: ServiceRuntime?
        get() = ServiceController.runtime

    override val homeDirPath: String
        get() = GlobalState.application.filesDir.path

    override val sdkInt: Int
        get() = android.os.Build.VERSION.SDK_INT

    fun attachFlutterEngine(engine: FlutterEngine) {
        flutterEngine = engine
    }

    fun detachFlutterEngine(engine: FlutterEngine): Boolean {
        if (flutterEngine !== engine) {
            return false
        }
        flutterEngine = null
        return true
    }

    override fun log(message: String) = GlobalState.log(message)

    override fun showToast(message: String) = GlobalState.application.showToast(message)

    override fun updateNotificationParams(params: NotificationParams) =
        ServiceConfig.updateNotificationParams(params)

    override fun loadSharedState(): SharedState = GlobalState.application.sharedState

    override fun isVpnPermissionGranted(): Boolean =
        VpnService.prepare(GlobalState.application) == null

    override fun isLocalNetworkPermissionGranted(): Boolean =
        sdkInt < Build.VERSION_CODES.CINNAMON_BUN ||
            ContextCompat.checkSelfPermission(
                GlobalState.application,
                Manifest.permission.ACCESS_LOCAL_NETWORK,
            ) == PackageManager.PERMISSION_GRANTED

    // Detach runs on the main thread too, so a start sent from it never meets a destroyed engine.
    override fun tile(): TileGateway? {
        val engine = flutterEngine ?: return null
        val plugin = engine.plugin<TilePlugin>() ?: return null
        return TileGateway { onAnswered ->
            mainHandler.post {
                if (flutterEngine === engine) plugin.handleStart(onAnswered) else onAnswered()
            }
        }
    }

    override fun app(): AppGateway? = flutterEngine?.plugin<AppPlugin>()?.let { plugin ->
        object : AppGateway {
            override fun requestNotificationPermission(callback: (Boolean) -> Unit) =
                plugin.requestNotificationPermission(callback)

            override fun requestLocalNetworkPermission(callback: (Boolean) -> Unit) =
                plugin.requestLocalNetworkPermission(callback)

            override fun prepareVpn(
                enable: Boolean,
                isCurrent: () -> Boolean,
                callback: (Boolean) -> Unit,
            ) = plugin.prepareVpn(enable, isCurrent, callback)

            override fun cancelVpnPreparation(callback: (Boolean) -> Unit) =
                plugin.cancelVpnPreparation(callback)

            override fun explainVpnRefusal(isCurrent: () -> Boolean) =
                plugin.explainVpnRefusal(isCurrent)
        }
    }

    override fun notifyStopped() {
        flutterEngine?.plugin<ServicePlugin>()?.notifyStopped()
    }

    override fun notifyStopRequested() {
        flutterEngine?.plugin<ServicePlugin>()?.notifyStopRequested()
    }

    override suspend fun quickSetup(initParams: String, setupParams: String): Result<String> =
        ServiceController.quickSetup(initParams, setupParams)

    override suspend fun startService(options: VpnOptions): Boolean =
        ServiceController.start(options)

    override suspend fun stopService() = ServiceController.stop()
}
