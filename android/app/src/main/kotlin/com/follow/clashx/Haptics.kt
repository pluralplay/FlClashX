package com.follow.clashx

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlin.math.roundToInt
import kotlin.math.roundToLong

private const val STEP_MS = 50L
private const val PULSE_MS = 100L
private const val FAINTEST = 8
private const val PREFERENCES = "haptics"
private const val ENABLED = "enabled"

/** Steps that grow from barely felt to full strength over [durationMs], eased in. */
internal fun risingWaveform(durationMs: Long): Pair<LongArray, IntArray> {
    val steps = (durationMs / STEP_MS).coerceAtLeast(1).toInt()
    val amplitudes = IntArray(steps) { step ->
        val t = (step + 1).toDouble() / steps
        (FAINTEST + (255 - FAINTEST) * t * t).roundToInt()
    }
    return LongArray(steps) { STEP_MS } to amplitudes
}

/** For a motor without amplitude control: off/on pulses that lengthen as the gaps close. */
internal fun risingPulses(durationMs: Long): LongArray {
    val pulses = (durationMs / PULSE_MS).coerceAtLeast(1).toInt()
    val pattern = LongArray(pulses * 2)
    for (pulse in 0 until pulses) {
        val t = (pulse + 1).toDouble() / pulses
        val on = (PULSE_MS * (0.1 + 0.9 * t * t)).roundToLong().coerceIn(5, PULSE_MS)
        pattern[pulse * 2] = PULSE_MS - on
        pattern[pulse * 2 + 1] = on
    }
    return pattern
}

object Haptics {
    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun enabled(context: Context) = preferences(context).getBoolean(ENABLED, true)

    fun setEnabled(context: Context, activity: Activity?, value: Boolean) {
        preferences(context).edit().putBoolean(ENABLED, value).apply()
        activity?.let(::applyTo)
    }

    /** Flutter's HapticFeedback goes through the decor view, silent while its feedback is off. */
    fun applyTo(activity: Activity) {
        activity.window.decorView.isHapticFeedbackEnabled = enabled(activity)
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }?.takeIf { it.hasVibrator() }

    fun rise(context: Context, durationMs: Long) {
        if (!enabled(context)) return
        val vibrator = vibrator(context) ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            vibrator.vibrate(risingPulses(durationMs), -1)
            return
        }
        val effect = if (vibrator.hasAmplitudeControl()) {
            val (timings, amplitudes) = risingWaveform(durationMs)
            VibrationEffect.createWaveform(timings, amplitudes, -1)
        } else {
            VibrationEffect.createWaveform(risingPulses(durationMs), -1)
        }
        vibrator.vibrate(effect)
    }

    fun stop(context: Context) {
        vibrator(context)?.cancel()
    }
}
