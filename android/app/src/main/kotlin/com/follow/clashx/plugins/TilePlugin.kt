package com.follow.clashx.plugins

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class TilePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    
    companion object {
        private const val TAG = "TilePlugin"
        
        // Latch to signal when Dart side is ready
        @Volatile
        private var readyLatch: CountDownLatch? = null
        
        // Pending action to execute when ready
        @Volatile
        private var pendingAction: PendingAction? = null
        
        enum class PendingAction {
            START, STOP
        }
        
        /**
         * Set a pending action to be executed when Dart is ready.
         * This is called from GlobalState when serviceEngine is being initialized.
         */
        fun setPendingAction(action: PendingAction) {
            Log.d(TAG, "setPendingAction: $action")
            pendingAction = action
            readyLatch = CountDownLatch(1)
        }
        
        /**
         * Wait for Dart side to be ready with timeout.
         * Returns true if ready, false if timeout.
         */
        fun waitForReady(timeoutMs: Long = 10000): Boolean {
            val latch = readyLatch ?: return true
            Log.d(TAG, "waitForReady: waiting up to ${timeoutMs}ms")
            val result = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            Log.d(TAG, "waitForReady: result=$result")
            return result
        }
        
        /**
         * Clear pending state after action is handled.
         */
        fun clearPendingState() {
            Log.d(TAG, "clearPendingState")
            pendingAction = null
            readyLatch = null
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine")
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tile")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine")
        handleDetached()
        channel.setMethodCallHandler(null)
    }

    fun handleStart() {
        Log.d(TAG, "handleStart: invoking 'start' on channel")
        channel.invokeMethod("start", null)
    }

    fun handleStop() {
        Log.d(TAG, "handleStop: invoking 'stop' on channel")
        channel.invokeMethod("stop", null)
    }

    private fun handleDetached() {
        Log.d(TAG, "handleDetached: invoking 'detached' on channel")
        channel.invokeMethod("detached", null)
    }


    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "updateTile" -> {
                updateTile()
                result.success(null)
            }
            "serviceReady" -> {
                handleServiceReady()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
    
    private fun updateTile() {
        Log.d(TAG, "updateTile: syncing status")
        // Force tile service to refresh its state
        com.follow.clashx.GlobalState.syncStatus()
    }
    
    private fun handleServiceReady() {
        Log.d(TAG, "handleServiceReady called, pendingAction=$pendingAction")
        
        // Signal that Dart is ready
        readyLatch?.countDown()
        
        // Execute pending action if any
        val action = pendingAction
        if (action != null) {
            Log.d(TAG, "Executing pending action: $action")
            when (action) {
                PendingAction.START -> handleStart()
                PendingAction.STOP -> handleStop()
            }
            clearPendingState()
        }
    }
}