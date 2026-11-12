package com.follow.clashx.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RequestCodesTest {
    @Test
    fun `the answer to a replaced launch does not answer the newer one`() {
        val codes = RequestCodes(first = 1100, count = 64)
        val replaced = codes.issue()!!
        val latest = codes.issue()!!

        assertFalse(codes.answers(replaced))
        assertTrue(codes.answers(latest))
        assertFalse(codes.answers(latest))
    }

    @Test
    fun `answered codes stay in their range and wrap around`() {
        val codes = RequestCodes(first = 10, count = 2)

        val issued = List(3) { codes.issue()!!.also(codes::answers) }

        assertEquals(listOf(10, 11, 10), issued)
        assertTrue(10 in codes)
        assertFalse(12 in codes)
        assertFalse(9 in codes)
    }

    @Test
    fun `a code whose dialog never answered is not handed out again`() {
        val codes = RequestCodes(first = 10, count = 2)
        val open = codes.issue()!!
        val answered = codes.issue()!!
        codes.answers(answered)

        val latest = codes.issue()

        assertEquals(answered, latest)
        assertFalse(codes.answers(open))
        assertTrue(codes.answers(latest!!))
    }

    @Test
    fun `no code is handed out while every one still waits for its answer`() {
        val codes = RequestCodes(first = 10, count = 2)
        val first = codes.issue()
        codes.issue()

        assertNull(codes.issue())
        codes.answers(first!!)
        assertEquals(first, codes.issue())
    }

    @Test
    fun `a reset frees the codes an activity that is gone can no longer answer`() {
        val codes = RequestCodes(first = 10, count = 2)
        codes.issue()
        codes.issue()

        codes.reset()

        assertEquals(10, codes.issue())
    }

    @Test
    fun `a request that launched nothing leaves no launch to answer`() {
        val codes = RequestCodes(first = 1100, count = 64)
        val earlier = codes.issue()!!

        codes.forget()

        assertFalse(codes.answers(earlier))
    }
}
