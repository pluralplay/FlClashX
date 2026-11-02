package com.follow.clashx.common

import java.util.concurrent.atomic.AtomicReference

/**
 * Every request mints a fresh [Token]. Work that was started for an older token is obsolete once a
 * newer request arrives, so callers check [isCurrent] before applying a result and roll back with
 * [resetToStopped], which only wins while the token is still the latest one.
 */
class RunIntentArbiter(initialRunning: Boolean = false) {
    class Token internal constructor(
        val running: Boolean,
        internal val resetOf: Token? = null,
    )

    private val latest = AtomicReference(Token(initialRunning))

    val isRunningRequested: Boolean
        get() = latest.get().running

    fun current(): Token = latest.get()

    fun request(running: Boolean): Token = Token(running).also(latest::set)

    fun isCurrent(token: Token): Boolean = latest.get() === token

    /** Rolling [token] back with [resetToStopped] is no newer request; any other change is. */
    fun isLatestRequest(token: Token): Boolean {
        val current = latest.get()
        return current === token || current.resetOf === token
    }

    fun resetToStopped(token: Token): Boolean =
        latest.compareAndSet(token, Token(running = false, resetOf = token))
}
