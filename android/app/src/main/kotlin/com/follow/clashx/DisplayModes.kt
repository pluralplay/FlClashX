package com.follow.clashx

data class DisplayModeInfo(
    val id: Int,
    val width: Int,
    val height: Int,
    val refreshRate: Float,
)

/** The fastest mode at [current]'s resolution, or null when the panel offers only one rate there. */
fun fastestModeId(current: DisplayModeInfo, modes: List<DisplayModeInfo>): Int? {
    val sameSize = modes.filter { it.width == current.width && it.height == current.height }
    val best = sameSize.maxByOrNull { it.refreshRate } ?: return null
    val slowest = sameSize.minOf { it.refreshRate }
    return if (best.refreshRate - slowest > 0.5f) best.id else null
}
