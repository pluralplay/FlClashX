package com.follow.clashx.service.models

data class NotificationParams(
    val title: String = "FlClashX",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
    val appVisible: Boolean = true,
)
