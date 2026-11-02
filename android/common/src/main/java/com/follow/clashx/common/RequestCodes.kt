package com.follow.clashx.common

/** Main thread only: the result of a launch a newer one replaced must not answer the newer. */
class RequestCodes(private val first: Int, private val count: Int) {
    private var next = 0
    private var current: Int? = null

    fun issue(): Int {
        val code = first + next
        next = (next + 1) % count
        current = code
        return code
    }

    operator fun contains(code: Int): Boolean = code in first until first + count

    fun answers(code: Int): Boolean {
        if (code != current) {
            return false
        }
        current = null
        return true
    }

    fun forget() {
        current = null
    }
}
