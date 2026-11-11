package com.follow.clashx

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HapticsTest {
    @Test
    fun `the waveform spans the duration and only grows, up to full strength`() {
        val (timings, amplitudes) = risingWaveform(4500)

        assertEquals(4500, timings.sum())
        assertTrue(amplitudes.first() < 20)
        assertEquals(255, amplitudes.last())
        assertTrue(amplitudes.toList().zipWithNext().all { (a, b) -> a <= b })
    }

    @Test
    fun `the pulses span the duration and lengthen as the gaps close`() {
        val pattern = risingPulses(600)
        val gaps = pattern.filterIndexed { index, _ -> index % 2 == 0 }
        val pulses = pattern.filterIndexed { index, _ -> index % 2 == 1 }

        assertEquals(600, pattern.sum())
        assertTrue(pulses.zipWithNext().all { (a, b) -> a <= b })
        assertTrue(gaps.zipWithNext().all { (a, b) -> a >= b })
        assertEquals(0, gaps.last())
    }
}
