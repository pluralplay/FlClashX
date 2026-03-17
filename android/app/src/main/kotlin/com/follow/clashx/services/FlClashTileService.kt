package com.follow.clashx.services

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.lifecycle.Observer
import com.follow.clashx.GlobalState
import com.follow.clashx.RunState


@RequiresApi(Build.VERSION_CODES.N)
class FlClashXTileService : TileService() {

    companion object {
        private const val TAG = "FlClashTileService"
    }

    private val observer = Observer<RunState> { runState ->
        Log.d(TAG, "Observer: runState changed to $runState")
        updateTile(runState)
    }

    private fun updateTile(runState: RunState) {
        Log.d(TAG, "updateTile called: runState=$runState")
        if (qsTile != null) {
            // Check if there's an active profile first
            val hasProfile = GlobalState.hasActiveProfile()
            Log.d(TAG, "hasProfile=$hasProfile")
            
            qsTile.state = if (!hasProfile) {
                // No profile selected - tile unavailable
                Log.d(TAG, "Setting tile to UNAVAILABLE (no profile)")
                Tile.STATE_UNAVAILABLE
            } else {
                // Profile exists - show state based on VPN status
                val state = when (runState) {
                    RunState.START -> Tile.STATE_ACTIVE
                    RunState.PENDING -> Tile.STATE_UNAVAILABLE
                    RunState.STOP -> Tile.STATE_INACTIVE
                }
                Log.d(TAG, "Setting tile state based on runState: $state")
                state
            }
            qsTile.updateTile()
        } else {
            Log.w(TAG, "qsTile is null, cannot update")
        }
    }

    override fun onStartListening() {
        Log.d(TAG, "onStartListening called")
        super.onStartListening()
        GlobalState.syncStatus()
        val currentState = GlobalState.runState.value
        Log.d(TAG, "Current runState: $currentState")
        currentState?.let { updateTile(it) }
        GlobalState.runState.observeForever(observer)
        Log.d(TAG, "Observer attached")
    }

    override fun onStopListening() {
        Log.d(TAG, "onStopListening called")
        GlobalState.runState.removeObserver(observer)
        super.onStopListening()
    }

    override fun onClick() {
        Log.d(TAG, "onClick called, current tile state: ${qsTile?.state}")
        
        // Use unlockAndRun to prevent service from being killed during long operations
        unlockAndRun {
            Log.d(TAG, "Inside unlockAndRun")
            when (qsTile?.state) {
                Tile.STATE_INACTIVE -> {
                    Log.d(TAG, "Tile INACTIVE -> calling handleStart()")
                    GlobalState.handleStart()
                }
                Tile.STATE_ACTIVE -> {
                    Log.d(TAG, "Tile ACTIVE -> calling handleStop()")
                    GlobalState.handleStop()
                }
                Tile.STATE_UNAVAILABLE -> {
                    // Tile is unavailable (no profile or pending operation) - ignore click
                    Log.d(TAG, "Tile UNAVAILABLE -> ignoring click")
                }
                else -> {
                    // qsTile is null, try to toggle anyway
                    Log.d(TAG, "Tile state null -> calling handleToggle()")
                    GlobalState.handleToggle()
                }
            }
        }
    }

    override fun onTileRemoved() {
        Log.d(TAG, "onTileRemoved called")
        super.onTileRemoved()
    }

    override fun onTileAdded() {
        Log.d(TAG, "onTileAdded called")
        super.onTileAdded()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy called")
        GlobalState.runState.removeObserver(observer)
        super.onDestroy()
    }
}