package com.follow.clashx.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RequestCodesTest {
    @Test
    fun `the answer to a replaced launch does not answer the newer one`() {
        val codes = RequestCodes(first = 1100, count = 64)
        val replaced = codes.issue()
        val latest = codes.issue()

        assertFalse(codes.answers(replaced))
        assertTrue(codes.answers(latest))
        assertFalse(codes.answers(latest))
    }

    @Test
    fun `codes stay in their range and wrap around`() {
        val codes = RequestCodes(first = 10, count = 2)

        assertEquals(listOf(10, 11, 10), List(3) { codes.issue() })
        assertTrue(10 in codes)
        assertFalse(12 in codes)
        assertFalse(9 in codes)
    }

    @Test
    fun `a request that launched nothing leaves no launch to answer`() {
        val codes = RequestCodes(first = 1100, count = 64)
        val earlier = codes.issue()

        codes.forget()

        assertFalse(codes.answers(earlier))
    }
}
