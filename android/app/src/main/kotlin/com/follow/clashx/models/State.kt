package com.follow.clashx.models

import com.follow.clashx.service.models.VpnOptions
import com.google.gson.annotations.SerializedName

data class SharedState(
    val startTip: String = "Starting VPN...",
    val stopTip: String = "Stopping VPN...",
    val localNetworkTip: String =
        "Local network permission denied: using the gvisor stack, LAN is unreachable.",
    val currentProfileName: String = "FlClashX",
    val stopText: String = "Stop",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
    val appVisible: Boolean = true,
    val vpnOptions: VpnOptions? = null,
    val setupParams: SetupParams? = null,
)

data class SetupParams(
    @SerializedName("test-url")
    val testUrl: String,
    @SerializedName("selected-map")
    val selectedMap: Map<String, String>,
    @SerializedName("skip-cert-verify")
    val skipCertVerify: Boolean = false,
)
