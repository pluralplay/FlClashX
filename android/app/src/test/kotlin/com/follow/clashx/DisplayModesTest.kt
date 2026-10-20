package com.follow.clashx

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DisplayModesTest {
    private val fhd60 = DisplayModeInfo(1, 1080, 2400, 60f)
    private val fhd90 = DisplayModeInfo(2, 1080, 2400, 90f)
    private val fhd120 = DisplayModeInfo(3, 1080, 2400, 120f)
    private val qhd144 = DisplayModeInfo(4, 1440, 3200, 144f)

    @Test
    fun `picks the fastest mode of the current resolution`() {
        val modes = listOf(fhd60, fhd90, fhd120, qhd144)
        assertEquals(3, fastestModeId(fhd60, modes))
        assertEquals(3, fastestModeId(fhd120, modes))
    }

    @Test
    fun `a panel with a single rate has nothing to pin`() {
        assertNull(fastestModeId(fhd60, listOf(fhd60, qhd144)))
        assertNull(fastestModeId(fhd60, listOf(fhd60, fhd60.copy(id = 9, refreshRate = 60.2f))))
    }

    @Test
    fun `a mode missing from the list leaves the panel alone`() {
        assertNull(fastestModeId(fhd60, emptyList()))
    }
}
