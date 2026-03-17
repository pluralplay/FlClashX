package com.follow.clashx.plugins

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import com.follow.clashx.FlClashXApplication
import com.follow.clashx.GlobalState
import com.follow.clashx.RunState
import com.follow.clashx.core.Core
import com.follow.clashx.extensions.awaitResult
import com.follow.clashx.extensions.resolveDns
import com.follow.clashx.models.StartForegroundParams
import com.follow.clashx.models.VpnOptions
import com.follow.clashx.services.BaseServiceInterface
import com.follow.clashx.services.FlClashXService
import com.follow.clashx.services.FlClashXVpnService
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import kotlin.concurrent.withLock

data object VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var flutterMethodChannel: MethodChannel
    private var flClashXService: BaseServiceInterface? = null
    private var options: VpnOptions? = null
    private var isBind: Boolean = false
    private lateinit var scope: CoroutineScope
    private var lastStartForegroundParams: StartForegroundParams? = null
    private var timerJob: Job? = null
    private val uidPageNameMap = mutableMapOf<Int, String>()

    private val connectivity by lazy {
        FlClashXApplication.getAppContext().getSystemService<ConnectivityManager>()
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            isBind = true
            flClashXService = when (service) {
                is FlClashXVpnService.LocalBinder -> service.getService()
                is FlClashXService.LocalBinder -> service.getService()
                else -> throw Exception("invalid binder")
            }
            handleStartService()
        }

        override fun onServiceDisconnected(arg: ComponentName) {
            isBind = false
            flClashXService = null
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(Dispatchers.Default)
        scope.launch {
            registerNetworkCallback()
        }
        flutterMethodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "vpn")
        flutterMethodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        unRegisterNetworkCallback()
        flutterMethodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val data = call.argument<String>("data")
                result.success(handleStart(Gson().fromJson(data, VpnOptions::class.java)))
            }

            "stop" -> {
                handleStop()
                result.success(true)
            }

            "showSubscriptionNotification" -> {
                val title = call.argument<String>("title") ?: ""
                val message = call.argument<String>("message") ?: ""
                val actionLabel = call.argument<String>("actionLabel") ?: ""
                val actionUrl = call.argument<String>("actionUrl") ?: ""
                showSubscriptionNotification(title, message, actionLabel, actionUrl)
                result.success(true)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    fun handleStart(options: VpnOptions): Boolean {
        onUpdateNetwork();
        if (options.enable != this.options?.enable) {
            this.flClashXService = null
        }
        this.options = options
        when (options.enable) {
            true -> handleStartVpn()
            false -> handleStartService()
        }
        return true
    }

    private fun handleStartVpn() {
        GlobalState.getCurrentAppPlugin()?.requestVpnPermission {
            handleStartService()
        }
    }

    fun requestGc() {
        flutterMethodChannel.invokeMethod("gc", null)
    }

    val networks = mutableSetOf<Network>()

    fun onUpdateNetwork() {
        val dns = networks.flatMap { network ->
            connectivity?.resolveDns(network) ?: emptyList()
        }.toSet().joinToString(",")
        scope.launch {
            withContext(Dispatchers.Main) {
                flutterMethodChannel.invokeMethod("dnsChanged", dns)
            }
        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            networks.add(network)
            onUpdateNetwork()
        }

        override fun onLost(network: Network) {
            networks.remove(network)
            onUpdateNetwork()
        }
    }

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private fun registerNetworkCallback() {
        networks.clear()
        connectivity?.registerNetworkCallback(request, callback)
    }

    private fun unRegisterNetworkCallback() {
        connectivity?.unregisterNetworkCallback(callback)
        networks.clear()
        onUpdateNetwork()
    }

    private suspend fun startForeground() {
        GlobalState.runLock.lock()
        try {
            if (GlobalState.runState.value != RunState.START) return
            val data = flutterMethodChannel.awaitResult<String>("getStartForegroundParams")
            val startForegroundParams = if (data != null) Gson().fromJson(
                data, StartForegroundParams::class.java
            ) else StartForegroundParams(
                title = "", server = "", content = ""
            )
            if (lastStartForegroundParams != startForegroundParams) {
                lastStartForegroundParams = startForegroundParams
                flClashXService?.startForeground(
                    startForegroundParams.title,
                    startForegroundParams.server,
                    startForegroundParams.content,
                )
            }
        } finally {
            GlobalState.runLock.unlock()
        }
    }

    private fun startForegroundJob() {
        stopForegroundJob()
        timerJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                startForeground()
                delay(1000)
            }
        }
    }

    private fun stopForegroundJob() {
        timerJob?.cancel()
        timerJob = null
    }


    suspend fun getStatus(): Boolean? {
        return withContext(Dispatchers.Default) {
            flutterMethodChannel.awaitResult<Boolean>("status", null)
        }
    }

    private fun handleStartService() {
        if (flClashXService == null) {
            bindService()
            return
        }
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.START) return
            GlobalState.runState.value = RunState.START
            val fd = flClashXService?.start(options!!)
            Core.startTun(
                fd = fd ?: 0,
                protect = this::protect,
                resolverProcess = this::resolverProcess,
            )
            startForegroundJob()
        }
    }

    private fun protect(fd: Int): Boolean {
        return (flClashXService as? FlClashXVpnService)?.protect(fd) == true
    }

    private fun resolverProcess(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
        uid: Int,
    ): String {
        val nextUid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
        } else {
            uid
        }
        if (nextUid == -1) {
            return ""
        }
        if (!uidPageNameMap.containsKey(nextUid)) {
            uidPageNameMap[nextUid] =
                FlClashXApplication.getAppContext().packageManager?.getPackagesForUid(nextUid)
                    ?.first() ?: ""
        }
        return uidPageNameMap[nextUid] ?: ""
    }

    fun handleStop() {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.STOP) return
            GlobalState.runState.value = RunState.STOP
            flClashXService?.stop()
            stopForegroundJob()
            Core.stopTun()
            GlobalState.handleTryDestroy()
        }
    }

    private fun bindService() {
        if (isBind) {
            FlClashXApplication.getAppContext().unbindService(connection)
        }
        val intent = when (options?.enable == true) {
            true -> Intent(FlClashXApplication.getAppContext(), FlClashXVpnService::class.java)
            false -> Intent(FlClashXApplication.getAppContext(), FlClashXService::class.java)
        }
        FlClashXApplication.getAppContext().bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

    private fun showSubscriptionNotification(title: String, message: String, actionLabel: String, actionUrl: String) {
        val context = FlClashXApplication.getAppContext()
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel for subscription alerts (Android O+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL,
                "Subscription Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications about subscription expiration"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Create intent for action button (open URL)
        val actionIntent = Intent(Intent.ACTION_VIEW, Uri.parse(actionUrl))
        val actionPendingIntent = PendingIntent.getActivity(
            context,
            0,
            actionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create intent to open app when notification is tapped
        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            1,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openAppPendingIntent)
        
        // Only add action button if actionLabel is not empty
        if (actionLabel.isNotEmpty() && actionUrl.isNotEmpty()) {
            builder.addAction(0, actionLabel, actionPendingIntent)
        }

        notificationManager.notify(GlobalState.SUBSCRIPTION_NOTIFICATION_ID, builder.build())
    }
}