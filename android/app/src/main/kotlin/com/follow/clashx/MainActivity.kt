package com.follow.clashx

import com.follow.clashx.plugins.AppPlugin
import com.follow.clashx.plugins.BatteryPlugin
import com.follow.clashx.plugins.ServicePlugin
import com.follow.clashx.plugins.TilePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val highRefreshRate by lazy { HighRefreshRate(this) }

    override fun onResume() {
        super.onResume()
        highRefreshRate.pin()
    }

    override fun onPause() {
        highRefreshRate.release()
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(BatteryPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        ServiceState.attachFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        flutterEngine?.let(ServiceState::detachFlutterEngine)
        super.onDestroy()
    }
}
