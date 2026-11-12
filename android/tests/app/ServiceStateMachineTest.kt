package com.follow.clashx

import com.follow.clashx.common.AccessControlMode
import com.follow.clashx.models.SetupParams
import com.follow.clashx.models.SharedState
import com.follow.clashx.service.models.AccessControlProps
import com.follow.clashx.service.models.NotificationParams
import com.follow.clashx.service.models.VpnOptions
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test

private fun vpnOptions(enable: Boolean = true, stack: String = "gvisor") = VpnOptions(
    enable = enable,
    port = 7890,
    ipv6 = false,
    dnsHijacking = false,
    accessControlProps = AccessControlProps(
        enable = false,
        mode = AccessControlMode.ACCEPT_SELECTED,
        acceptList = emptyList(),
        rejectList = emptyList(),
    ),
    allowBypass = false,
    systemProxy = true,
    bypassDomain = emptyList(),
    stack = stack,
    routeAddress = emptyList(),
)

private fun configuredState(enable: Boolean = true, stack: String = "gvisor") = SharedState(
    vpnOptions = vpnOptions(enable, stack),
    setupParams = SetupParams(testUrl = "https://example.com", selectedMap = emptyMap()),
)

private const val STARTED_AT = 1_700_000_000_000L

private class FakeTile : TileGateway {
    var startCount = 0
    private val answers = mutableListOf<() -> Unit>()

    override fun handleStart(onAnswered: () -> Unit) {
        startCount++
        answers += onAnswered
    }

    fun answer() = answers.removeAt(0).invoke()

    fun answerLatest() = answers.removeAt(answers.lastIndex).invoke()
}

private class FakeApp(
    private val notificationGranted: Boolean = true,
    private val localNetworkGranted: Boolean = true,
    private val vpnGranted: Boolean = true,
    private val holdVpnPreparation: Boolean = false,
    private val holdOnlyVpn: Boolean = false,
    private val holdExplanation: Boolean = false,
) : AppGateway {
    var beforeVpnPrepared: (() -> Unit)? = null
    var preparations = 0
    var cancelledPreparations = 0
    var localNetworkRequests = 0
    var explainedRefusals = 0
    private var heldExplanation: (() -> Boolean)? = null

    private var heldCallback: ((Boolean) -> Unit)? = null
    private val heldPreparations = mutableListOf<(Boolean) -> Unit>()

    override fun requestNotificationPermission(callback: (Boolean) -> Unit) =
        callback(notificationGranted)

    override fun requestLocalNetworkPermission(callback: (Boolean) -> Unit) {
        localNetworkRequests++
        callback(localNetworkGranted)
    }

    var mainThreadHop: (() -> Unit)? = null

    /** What the request check said once the main thread took the preparation; AppPlugin acts on it. */
    var currentOnMainThread: Boolean? = null

    override fun prepareVpn(
        enable: Boolean,
        isCurrent: () -> Boolean,
        callback: (Boolean) -> Unit,
    ) {
        mainThreadHop?.invoke()
        currentOnMainThread = isCurrent()
        preparations++
        beforeVpnPrepared?.invoke()
        if (holdVpnPreparation && (enable || !holdOnlyVpn)) {
            heldCallback = callback
            heldPreparations += callback
            return
        }
        callback(vpnGranted)
    }

    override fun cancelVpnPreparation(callback: (Boolean) -> Unit) {
        cancelledPreparations++
        if (heldCallback === callback) {
            heldCallback = null
        }
    }

    override fun explainVpnRefusal(isCurrent: () -> Boolean) {
        heldExplanation = isCurrent
        if (!holdExplanation) {
            deliverExplanation()
        }
    }

    fun resolveHeldPreparation(granted: Boolean) {
        heldCallback?.invoke(granted)
    }

    /** The consent activity can answer after a cancellation was posted, so this ignores it. */
    fun answerPreparation(index: Int, granted: Boolean) = heldPreparations[index](granted)

    fun deliverExplanation() {
        if (heldExplanation?.invoke() == true) {
            explainedRefusals++
        }
        heldExplanation = null
    }
}

private class FakeHost(override val scope: CoroutineScope) : ServiceStateHost {
    var storedSharedState = configuredState()
    var setupResult: Result<String> = Result.success("")
    var startSucceeds = true
    var vpnPermissionGranted = true
    var localNetworkPermissionGranted = true
    var runsAsVpn: Boolean? = null
    var tile: TileGateway? = null
    var app: AppGateway? = null
    var appLookups = 0
    var onAppLookup: ((Int) -> Unit)? = null
    var duringSetup: (suspend () -> Unit)? = null
    var beforeStartService: (() -> Unit)? = null
    var lastStartOptions: VpnOptions? = null

    override var runtime: ServiceRuntime? = null
    override val homeDirPath = "/data/user/0/com.follow.clashx/files"
    override val sdkInt = 34

    val toasts = mutableListOf<String>()
    val logs = mutableListOf<String>()
    val notificationParams = mutableListOf<NotificationParams>()
    var setupCalls = 0
    var startCalls = 0
    var stopCalls = 0
    var stoppedNotifications = 0
    var stopRequests = 0
    var lastInitParams: String? = null
    var lastSetupParams: String? = null

    override fun log(message: String) {
        logs += message
    }

    override fun showToast(message: String) {
        toasts += message
    }

    override fun updateNotificationParams(params: NotificationParams) {
        notificationParams += params
    }

    override fun loadSharedState(): SharedState = storedSharedState

    override fun isVpnPermissionGranted(): Boolean = vpnPermissionGranted

    override fun isLocalNetworkPermissionGranted(): Boolean = localNetworkPermissionGranted

    override fun tile(): TileGateway? = tile

    override fun app(): AppGateway? {
        onAppLookup?.invoke(++appLookups)
        return app
    }

    override fun notifyStopped() {
        stoppedNotifications++
    }

    override fun notifyStopRequested() {
        stopRequests++
    }

    override suspend fun quickSetup(initParams: String, setupParams: String): Result<String> {
        setupCalls++
        lastInitParams = initParams
        lastSetupParams = setupParams
        duringSetup?.invoke()
        return setupResult
    }

    override suspend fun startService(options: VpnOptions): Boolean {
        startCalls++
        lastStartOptions = options
        beforeStartService?.invoke()
        if (!startSucceeds) {
            return false
        }
        runtime = ServiceRuntime(vpn = runsAsVpn ?: options.enable, startedAtMillis = STARTED_AT)
        return true
    }

    override suspend fun stopService() {
        stopCalls++
        runtime = null
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class ServiceStateMachineTest {

    @Test
    fun `initParams spells the keys the Go wrapper expects`() {
        val json = ServiceStateMachine.initParams("/files", 34)

        assertEquals("""{"home-dir":"/files","version":34}""", json)
    }

    @Test
    fun `notification params come straight off the shared state`() {
        val params = ServiceStateMachine.notificationParams(
            SharedState(
                currentProfileName = "Work",
                stopText = "Disconnect",
            ),
        )

        assertEquals(NotificationParams("Work", "Disconnect"), params)
    }

    @Test
    fun `notification params carry the stop action switch`() {
        val params = ServiceStateMachine.notificationParams(
            SharedState(showStopAction = false),
        )

        assertEquals(false, params.showStopAction)
    }

    @Test
    fun `the run time is reported only while a run is both requested and up`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertEquals(0L, machine.awaitRunTime())

        machine.requestStart().await()
        assertEquals(STARTED_AT, machine.awaitRunTime())

        machine.requestStop().await()
        assertEquals(0L, machine.awaitRunTime())
    }

    @Test
    fun `a stop request reads as STOPPING until the service is down`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        val stop = machine.requestStop()

        assertEquals(RunState.STOPPING, machine.runState.value)
        assertEquals(0L, machine.awaitRunTime())
        assertTrue(stop.await())
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a start request drives the service to STARTED`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertTrue(machine.requestStart().await())
        assertEquals(RunState.STARTED, machine.runState.value)
        assertEquals(1, host.startCalls)
    }

    @Test
    fun `a start that the service refuses settles back to STOPPED`() = runTest {
        val host = FakeHost(backgroundScope)
        host.startSucceeds = false
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertFalse(machine.isRunRequested)
        assertEquals(1, host.stoppedNotifications)
    }

    @Test
    fun `a start without stored vpn options never reaches the service`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `a denied notification permission cancels the start`() = runTest {
        val host = FakeHost(backgroundScope)
        host.app = FakeApp(notificationGranted = false)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(1, host.stoppedNotifications)
    }

    @Test
    fun `a start repeated on a settled run asks for nothing and keeps the service`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        val token = machine.captureRequestToken()
        val app = FakeApp(notificationGranted = false)
        host.app = app

        assertTrue(machine.requestStart().await())

        assertTrue(machine.captureRequestToken() === token)
        assertEquals(0, app.localNetworkRequests)
        assertEquals(1, host.startCalls)
        assertEquals(0, host.stopCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a start that changes the service kind is refused down to STOPPED`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))
        machine.requestStart().await()
        machine.syncSharedState(configuredState(enable = true))
        host.app = FakeApp(vpnGranted = false)

        assertFalse(machine.requestStart().await())

        assertEquals(1, host.stopCalls)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertFalse(machine.isRunRequested)
    }

    /** The explanation reaches the main thread only after the refused start was rolled back. */
    @Test
    fun `a denied vpn permission is explained by the app in front`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(vpnGranted = false, holdExplanation = true)
        host.app = app
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        app.deliverExplanation()
        assertEquals(1, app.explainedRefusals)
        assertFalse(host.toasts.contains(VPN_PERMISSION_MESSAGE))
    }

    @Test
    fun `a denied vpn permission is not explained once a stop superseded the start`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(vpnGranted = false, holdExplanation = true)
        host.app = app
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        machine.requestStop().await()
        app.deliverExplanation()

        assertEquals(0, app.explainedRefusals)
        assertFalse(host.toasts.contains(VPN_PERMISSION_MESSAGE))
    }

    @Test
    fun `a denied vpn permission cancels the start`() = runTest {
        val host = FakeHost(backgroundScope)
        host.app = FakeApp(vpnGranted = false)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
        assertEquals(1, host.stoppedNotifications)
    }

    /** Flutter opened the Core's listeners before asking, and may be gone before it hears back. */
    @Test
    fun `a start refused before any service came up closes the core without passing STOPPING`() =
        runTest {
            val host = FakeHost(backgroundScope)
            host.app = FakeApp(vpnGranted = false)
            val machine = ServiceStateMachine(host)
            machine.syncSharedState(configuredState())
            val states = mutableListOf<RunState>()
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                machine.runState.toList(states)
            }

            assertFalse(machine.requestStart().await())
            testScheduler.runCurrent()

            assertEquals(1, host.stopCalls)
            assertFalse(states.contains(RunState.STOPPING))
            assertEquals(RunState.STOPPED, machine.runState.value)
        }

    /**
     * Without a foreground app there is nobody to show the system consent dialog, so the machine
     * has to explain the refusal itself.
     */
    @Test
    fun `a missing vpn permission is reported when no app is attached`() = runTest {
        val host = FakeHost(backgroundScope)
        host.vpnPermissionGranted = false
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertFalse(machine.requestStart().await())
        assertTrue(host.toasts.contains(VPN_PERMISSION_MESSAGE))
    }

    @Test
    fun `a proxy-only start does not need the vpn permission`() = runTest {
        val host = FakeHost(backgroundScope)
        host.vpnPermissionGranted = false
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))

        assertTrue(machine.requestStart().await())
        assertEquals(1, host.startCalls)
    }

    /** Android 17 drops the kernel hop system/mixed rely on until the permission is granted. */
    @Test
    fun `a denied local network permission falls back to the gvisor stack`() = runTest {
        val host = FakeHost(backgroundScope)
        host.localNetworkPermissionGranted = false
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(stack = "system"))

        assertTrue(machine.requestStart().await())
        assertEquals("gvisor", host.lastStartOptions?.stack)
        assertTrue(host.toasts.contains(configuredState().localNetworkTip))
    }

    @Test
    fun `a granted local network permission keeps the chosen stack`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(stack = "mixed"))

        assertTrue(machine.requestStart().await())
        assertEquals("mixed", host.lastStartOptions?.stack)
        assertFalse(host.toasts.contains(configuredState().localNetworkTip))
    }

    @Test
    fun `a proxy-only start keeps its stack without the local network permission`() = runTest {
        val host = FakeHost(backgroundScope)
        host.localNetworkPermissionGranted = false
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false, stack = "system"))

        assertTrue(machine.requestStart().await())
        assertEquals("system", host.lastStartOptions?.stack)
        assertFalse(host.toasts.contains(configuredState().localNetworkTip))
    }

    @Test
    fun `the local network prompt is asked once and never blocks the start`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(localNetworkGranted = false)
        host.app = app
        host.localNetworkPermissionGranted = false
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(stack = "system"))

        assertTrue(machine.requestStart().await())
        assertEquals(1, app.localNetworkRequests)
        assertEquals(1, host.startCalls)
        assertEquals("gvisor", host.lastStartOptions?.stack)
    }

    @Test
    fun `a stop request drives the service to STOPPED`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        assertTrue(machine.requestStop().await())
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(1, host.stopCalls)
        assertEquals(0, host.stoppedNotifications)
    }

    @Test
    fun `stopping an already stopped service touches nothing`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)

        assertTrue(machine.requestStop().await())
        assertEquals(0, host.stopCalls)
    }

    @Test
    fun `a stop that lands mid-preparation keeps the service stopped`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        val app = FakeApp()
        host.app = app
        app.beforeVpnPrepared = { machine.requestStop() }

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a start reports failure when a stop overtakes the service call`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        host.beforeStartService = { machine.requestStop() }

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.stoppedNotifications)
    }

    @Test
    fun `handleServiceLost clears the state for the token that observed the loss`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        val token = machine.captureRequestToken()
        host.runtime = null
        machine.handleServiceLost(token)

        assertEquals(RunState.STOPPED, machine.runState.value)
        assertFalse(machine.isRunRequested)
        assertEquals(1, host.stoppedNotifications)
    }

    /** The newer start still owns the intent, but nothing is running until it brings it up. */
    @Test
    fun `handleServiceLost keeps the intent of a start that raced ahead of it`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        val staleToken = machine.captureRequestToken()

        machine.requestStart().await()
        host.runtime = null
        machine.handleServiceLost(staleToken)

        assertTrue(machine.isRunRequested)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(0, host.stoppedNotifications)
    }

    @Test
    fun `handleServiceLost ignores a service that is running again`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        machine.handleServiceLost(machine.captureRequestToken())

        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `handleStartAction hands the start to the tile when one is attached`() = runTest {
        val host = FakeHost(backgroundScope)
        val tile = FakeTile()
        host.tile = tile
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertEquals(1, tile.startCount)
        assertEquals(0, host.setupCalls)
    }

    @Test
    fun `handleStartAction is a no-op while a run is already requested`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        val startsBefore = host.startCalls

        machine.handleStartAction()

        assertEquals(startsBefore, host.startCalls)
        assertEquals(0, host.setupCalls)
    }

    @Test
    fun `handleStartAction reports a missing configuration`() = runTest {
        val host = FakeHost(backgroundScope)
        host.storedSharedState = SharedState()
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertEquals(listOf(MISSING_CONFIG_MESSAGE), host.toasts)
        assertEquals(0, host.setupCalls)
        assertFalse(machine.isRunRequested)
    }

    @Test
    fun `handleStartAction loads the stored configuration and sets the core up`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertEquals(1, host.setupCalls)
        assertEquals(1, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
        assertEquals(
            ServiceStateMachine.initParams(host.homeDirPath, host.sdkInt),
            host.lastInitParams,
        )
        assertEquals(Gson().toJson(host.storedSharedState.setupParams), host.lastSetupParams)
    }

    @Test
    fun `a core that rejects the configuration reports its own message`() = runTest {
        val host = FakeHost(backgroundScope)
        host.setupResult = Result.success("proxy group not found")
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertTrue(host.toasts.contains("proxy group not found"))
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `a core setup that throws without a message falls back to the generic one`() = runTest {
        val host = FakeHost(backgroundScope)
        host.setupResult = Result.failure(RuntimeException("   "))
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertTrue(host.toasts.contains(INVALID_CONFIG_MESSAGE))
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `a service that refuses the start after a good setup is reported`() = runTest {
        val host = FakeHost(backgroundScope)
        host.startSucceeds = false
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertTrue(host.toasts.contains(START_FAILED_MESSAGE))
        assertFalse(machine.isRunRequested)
    }

    @Test
    fun `handleStopAction stops the service itself and reports it to Flutter`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        val tile = FakeTile()
        host.tile = tile

        machine.handleStopAction()

        assertEquals(0, tile.startCount)
        assertEquals(1, host.stopCalls)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(1, host.stoppedNotifications)
    }

    @Test
    fun `a toggle during the native setup cancels the start without reporting a failure`() =
        runTest {
            val host = FakeHost(backgroundScope)
            val machine = ServiceStateMachine(host)
            host.duringSetup = { machine.handleToggleAction() }

            machine.handleStartAction()

            assertEquals(1, host.setupCalls)
            assertEquals(0, host.startCalls)
            assertFalse(host.toasts.contains(START_FAILED_MESSAGE))
            assertFalse(machine.isRunRequested)
            assertEquals(RunState.STOPPED, machine.runState.value)
        }

    /** The setup already opened the Core's ports, so a start that ends there has to close them. */
    @Test
    fun `a native start that does not end up running tears the core setup down`() = runTest {
        val cancelled = FakeHost(backgroundScope)
        val cancelledMachine = ServiceStateMachine(cancelled)
        cancelled.duringSetup = { cancelledMachine.handleToggleAction() }
        cancelledMachine.handleStartAction()

        val refused = FakeHost(backgroundScope)
        refused.vpnPermissionGranted = false
        ServiceStateMachine(refused).handleStartAction()

        val rejected = FakeHost(backgroundScope)
        rejected.setupResult = Result.success("proxy group not found")
        ServiceStateMachine(rejected).handleStartAction()

        assertEquals(listOf(1, 1, 1), listOf(cancelled, refused, rejected).map { it.stopCalls })
    }

    @Test
    fun `a native start that runs leaves the core setup alone`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertEquals(0, host.stopCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a second start action during the native setup is ignored`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        host.duringSetup = { machine.handleStartAction() }

        machine.handleStartAction()

        assertEquals(1, host.setupCalls)
        assertEquals(1, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `handleStopAction is a no-op while nothing is running`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)

        machine.handleStopAction()

        assertEquals(0, host.stopCalls)
        assertTrue(host.toasts.isEmpty())
    }

    @Test
    fun `a stop while an excluded SSID holds the service down still reaches Flutter`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        machine.handleStopAction()

        assertEquals(0, host.stopCalls)
        assertEquals(0, host.stoppedNotifications)
        assertEquals(1, host.stopRequests)
    }

    @Test
    fun `handleStopAction announces itself before stopping`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState().copy(stopTip = "Stopping..."))
        machine.requestStart().await()

        machine.handleStopAction()

        assertEquals(listOf("Stopping..."), host.toasts)
        assertEquals(1, host.stopCalls)
    }

    @Test
    fun `handleToggleAction starts when stopped and stops when started`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)

        machine.handleToggleAction()
        assertEquals(1, host.startCalls)

        machine.handleToggleAction()
        assertEquals(1, host.stopCalls)
    }

    @Test
    fun `a revoke is ignored while no vpn service is active`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))
        machine.requestStart().await()

        machine.handleVpnRevokeAction()

        assertEquals(0, host.stopCalls)
    }

    @Test
    fun `a revoke stops the vpn service even with Flutter attached`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        host.tile = FakeTile()

        machine.handleVpnRevokeAction()

        assertEquals(1, host.stopCalls)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(1, host.stoppedNotifications)
    }

    @Test
    fun `a revoke stops the active vpn service`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        machine.handleVpnRevokeAction()

        assertEquals(1, host.stopCalls)
    }

    @Test
    fun `syncSharedState pushes the notification straight through`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)

        machine.syncSharedState(
            SharedState(
                currentProfileName = "Work",
                stopText = "Disconnect",
            ),
        )

        assertEquals(listOf(NotificationParams("Work", "Disconnect")), host.notificationParams)
    }

    @Test
    fun `a start that a stop overtakes never announces STARTED`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        val states = mutableListOf<RunState>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            machine.runState.toList(states)
        }
        host.beforeStartService = { machine.requestStop() }

        assertFalse(machine.requestStart().await())
        testScheduler.runCurrent()

        assertFalse(states.contains(RunState.STARTED))
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(null, host.runtime)
    }

    @Test
    fun `a start rolled back after the service came up stops it again`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        host.beforeStartService = {
            host.app = FakeApp(vpnGranted = false)
            machine.requestStart()
        }

        assertFalse(machine.requestStart().await())
        testScheduler.runCurrent()

        assertEquals(1, host.stopCalls)
        assertEquals(null, host.runtime)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertFalse(machine.captureRequestToken().running)
    }

    @Test
    fun `a start that overtakes another inside the binding window adopts the running service`() =
        runTest {
            val host = FakeHost(backgroundScope)
            val machine = ServiceStateMachine(host)
            machine.syncSharedState(configuredState())
            host.beforeStartService = {
                host.beforeStartService = null
                machine.requestStart()
            }

            machine.requestStart().await()
            testScheduler.runCurrent()

            assertEquals(1, host.startCalls)
            assertEquals(0, host.stopCalls)
            assertEquals(RunState.STARTED, machine.runState.value)
            assertTrue(machine.captureRequestToken().running)
        }

    @Test
    fun `a restart replaces the running service with one built from the current options`() =
        runTest {
            val host = FakeHost(backgroundScope)
            val machine = ServiceStateMachine(host)
            machine.syncSharedState(configuredState())
            machine.requestStart().await()
            val previous = host.runtime
            val states = mutableListOf<RunState>()
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                machine.runState.toList(states)
            }
            machine.syncSharedState(configuredState(stack = "mixed"))

            assertTrue(machine.requestRestart().await())
            testScheduler.runCurrent()

            assertEquals(1, host.stopCalls)
            assertEquals(2, host.startCalls)
            assertEquals("mixed", host.lastStartOptions?.stack)
            assertNotSame(previous, host.runtime)
            assertEquals(RunState.STARTED, machine.runState.value)
            assertFalse(states.contains(RunState.STOPPING) || states.contains(RunState.STOPPED))
            assertEquals(0, host.stoppedNotifications)
        }

    @Test
    fun `a restart while nothing runs only starts`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        assertTrue(machine.requestRestart().await())

        assertEquals(0, host.stopCalls)
        assertEquals(1, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    /** Flutter's old restart was exactly this pair, and its start adopted the run it meant to end. */
    @Test
    fun `a stop and a start that overtake a restart still end on a new service`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        val previous = host.runtime

        val restart = machine.requestRestart()
        machine.requestStop()
        val start = machine.requestStart()

        assertTrue(start.await())
        assertFalse(restart.await())
        assertEquals(1, host.stopCalls)
        assertEquals(2, host.startCalls)
        assertNotSame(previous, host.runtime)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a stop that overtakes a restart leaves the service stopped`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        val restart = machine.requestRestart()
        val stop = machine.requestStop()

        assertTrue(stop.await())
        assertFalse(restart.await())
        assertEquals(1, host.startCalls)
        assertEquals(null, host.runtime)
        assertFalse(machine.isRunRequested)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a restart asked twice in a row replaces the service once`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        val first = machine.requestRestart()
        val second = machine.requestRestart()

        assertTrue(second.await())
        assertFalse(first.await())
        assertEquals(1, host.stopCalls)
        assertEquals(2, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a start after a served restart adopts the new service`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        machine.requestRestart().await()
        machine.requestStop()

        assertTrue(machine.requestStart().await())

        assertEquals(1, host.stopCalls)
        assertEquals(2, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a restart whose new service fails reports the run stopped`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()
        host.startSucceeds = false

        assertFalse(machine.requestRestart().await())

        assertEquals(null, host.runtime)
        assertFalse(machine.isRunRequested)
        assertEquals(RunState.STOPPED, machine.runState.value)
        assertEquals(1, host.stoppedNotifications)
    }

    @Test
    fun `a start rebinds when the running service is not the one the options ask for`() = runTest {
        val host = FakeHost(backgroundScope)
        host.runsAsVpn = false
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        host.beforeStartService = {
            host.beforeStartService = null
            machine.requestStart()
        }

        machine.requestStart().await()
        testScheduler.runCurrent()

        assertEquals(2, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a stop releases a start that is waiting on the vpn consent`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(holdVpnPreparation = true)
        host.app = app
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        val start = machine.requestStart()
        testScheduler.runCurrent()
        assertEquals(0, host.startCalls)

        assertTrue(machine.requestStop().await())
        assertFalse(start.await())
        assertEquals(0, host.startCalls)
        assertEquals(1, app.cancelledPreparations)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a start a stop overtook on its way to the consent never asks for it`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(holdVpnPreparation = true)
        host.app = app
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        // The first lookup asks for notifications; the second is the consent's own.
        host.onAppLookup = { lookup -> if (lookup == 2) machine.requestStop() }

        val start = machine.requestStart()
        testScheduler.runCurrent()

        assertFalse(start.await())
        assertEquals(0, app.preparations)
        host.onAppLookup = null
        machine.requestStart()
        testScheduler.runCurrent()
        assertEquals(1, app.preparations)
    }

    @Test
    fun `a stop landing while the consent waits for the main thread keeps it closed`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(holdVpnPreparation = true)
        host.app = app
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        app.mainThreadHop = {
            app.mainThreadHop = null
            machine.requestStop()
        }

        val start = machine.requestStart()
        testScheduler.runCurrent()

        assertFalse(start.await())
        assertEquals(false, app.currentOnMainThread)

        machine.requestStart()
        testScheduler.runCurrent()
        assertEquals(true, app.currentOnMainThread)
    }

    @Test
    fun `a late consent for a stopped start leaves the next start's consent cancellable`() =
        runTest {
            val host = FakeHost(backgroundScope)
            val app = FakeApp(holdVpnPreparation = true)
            host.app = app
            val machine = ServiceStateMachine(host)
            machine.syncSharedState(configuredState())
            val first = machine.requestStart()
            testScheduler.runCurrent()
            assertTrue(machine.requestStop().await())
            assertFalse(first.await())
            val second = machine.requestStart()
            testScheduler.runCurrent()

            app.answerPreparation(0, true)
            assertTrue(machine.requestStop().await())
            testScheduler.runCurrent()

            assertTrue(second.isCompleted)
            assertFalse(second.await())
            assertEquals(2, app.cancelledPreparations)
            assertEquals(0, host.startCalls)
            assertEquals(RunState.STOPPED, machine.runState.value)
        }

    @Test
    fun `a start request that throws is logged and rolled back`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        host.beforeStartService = { throw IllegalStateException("binder died") }

        assertFalse(machine.requestStart().await())
        assertTrue(host.logs.any { it.contains("binder died") })
        assertFalse(machine.captureRequestToken().running)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a start handed to Flutter is a requested run until Flutter answers`() = runTest {
        val host = FakeHost(backgroundScope)
        host.tile = FakeTile()
        val machine = ServiceStateMachine(host)

        machine.handleStartAction()

        assertTrue(machine.isRunRequested)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a stop before Flutter sends back a handed-off start keeps the run off`() = runTest {
        val host = FakeHost(backgroundScope)
        host.tile = FakeTile()
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState().copy(stopTip = "Stopping..."))

        machine.handleStartAction()
        machine.handleStopAction()

        assertFalse(machine.requestStart().await())
        assertEquals(listOf("Stopping..."), host.toasts)
        assertEquals(0, host.startCalls)
        assertEquals(1, host.stopCalls)
        assertFalse(machine.isRunRequested)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `a stop that lands after Flutter's start was taken still wins`() = runTest {
        val host = FakeHost(backgroundScope)
        host.tile = FakeTile()
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.handleStartAction()

        val start = machine.requestStart()
        machine.handleStopAction()

        assertFalse(start.await())
        assertEquals(0, host.startCalls)
        assertFalse(machine.isRunRequested)
    }

    @Test
    fun `only the start Flutter carries back after a stop is refused`() = runTest {
        val host = FakeHost(backgroundScope)
        host.tile = FakeTile()
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.handleStartAction()
        machine.handleStopAction()

        assertFalse(machine.requestStart().await())
        assertTrue(machine.requestStart().await())
        assertEquals(1, host.startCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a handed-off start that Flutter sends back runs`() = runTest {
        val host = FakeHost(backgroundScope)
        val tile = FakeTile()
        host.tile = tile
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        machine.handleStartAction()
        assertTrue(machine.requestStart().await())
        tile.answer()
        testScheduler.runCurrent()

        assertEquals(1, host.startCalls)
        assertEquals(0, host.stopCalls)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a start Flutter declines is settled, so the next start is a fresh one`() = runTest {
        val host = FakeHost(backgroundScope)
        val tile = FakeTile()
        host.tile = tile
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.handleStartAction()

        tile.answer()
        testScheduler.runCurrent()
        assertFalse(machine.isRunRequested)
        machine.handleStopAction()

        assertTrue(machine.requestStart().await())
        assertEquals(1, host.startCalls)
    }

    @Test
    fun `a stopped start that Flutter declines refuses no later start`() = runTest {
        val host = FakeHost(backgroundScope)
        val tile = FakeTile()
        host.tile = tile
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.handleStartAction()
        machine.handleStopAction()

        tile.answer()
        testScheduler.runCurrent()

        assertTrue(machine.requestStart().await())
        assertEquals(1, host.startCalls)
    }

    @Test
    fun `Flutter going away settles the start it was handed`() = runTest {
        val host = FakeHost(backgroundScope)
        host.tile = FakeTile()
        val machine = ServiceStateMachine(host)
        machine.handleStartAction()

        machine.dropFlutterStart()
        testScheduler.runCurrent()

        assertFalse(machine.isRunRequested)
    }

    @Test
    fun `a second toggle while Flutter carries the start cancels it`() = runTest {
        val host = FakeHost(backgroundScope)
        val tile = FakeTile()
        host.tile = tile
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())

        machine.handleToggleAction()
        machine.handleToggleAction()

        assertEquals(1, tile.startCount)
        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
    }

    @Test
    fun `a command from Flutter settles a handed-off start, a stop as well`() = runTest {
        val host = FakeHost(backgroundScope)
        host.tile = FakeTile()
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.handleStartAction()
        machine.requestStop().await()

        machine.handleStopAction()

        assertTrue(machine.requestStart().await())
        assertEquals(1, host.startCalls)
    }

    @Test
    fun `Always-on starts a VPN run even when the app runs proxy-only`() = runTest {
        val host = FakeHost(backgroundScope)
        host.storedSharedState = configuredState(enable = false)
        val machine = ServiceStateMachine(host)

        machine.handleVpnStartRequested()

        assertEquals(true, host.lastStartOptions?.enable)
        assertEquals(true, host.runtime?.vpn)
        assertEquals(RunState.STARTED, machine.runState.value)
        assertTrue(machine.vpnDemandedBySystem.value)
    }

    @Test
    fun `Always-on turns a proxy-only run into a VPN one`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))
        machine.requestStart().await()
        assertEquals(false, host.runtime?.vpn)

        machine.handleVpnStartRequested()

        assertEquals(2, host.startCalls)
        assertEquals(true, host.runtime?.vpn)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `Always-on leaves a VPN run alone`() = runTest {
        val host = FakeHost(backgroundScope)
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState())
        machine.requestStart().await()

        machine.handleVpnStartRequested()

        assertEquals(1, host.startCalls)
    }

    @Test
    fun `Always-on during the native setup starts nothing past a failed setup`() = runTest {
        val host = FakeHost(backgroundScope)
        host.setupResult = Result.success("proxy group not found")
        val machine = ServiceStateMachine(host)
        host.duringSetup = { machine.handleVpnStartRequested() }

        machine.handleStartAction()

        assertEquals(0, host.startCalls)
        assertEquals(null, host.runtime)
        assertFalse(machine.isRunRequested)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `Always-on during the native setup starts one VPN once the setup is done`() = runTest {
        val host = FakeHost(backgroundScope)
        host.storedSharedState = configuredState(enable = false)
        val machine = ServiceStateMachine(host)
        var startsDuringSetup = -1
        host.duringSetup = {
            machine.handleVpnStartRequested()
            startsDuringSetup = host.startCalls
        }

        machine.handleStartAction()

        assertEquals(0, startsDuringSetup)
        assertEquals(1, host.startCalls)
        assertEquals(true, host.lastStartOptions?.enable)
        assertEquals(true, host.runtime?.vpn)
    }

    @Test
    fun `a start that read proxy options before Always-on asked comes up as a VPN`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(holdVpnPreparation = true)
        host.app = app
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))
        val start = machine.requestStart()
        testScheduler.runCurrent()

        backgroundScope.launch { machine.handleVpnStartRequested() }
        testScheduler.runCurrent()
        app.resolveHeldPreparation(true)
        testScheduler.runCurrent()
        app.resolveHeldPreparation(true)

        assertTrue(start.await())
        assertEquals(2, host.startCalls)
        assertEquals(true, host.lastStartOptions?.enable)
        assertEquals(true, host.runtime?.vpn)
        assertEquals(RunState.STARTED, machine.runState.value)
    }

    @Test
    fun `a stop during the VPN retry of a proxy start leaves nothing running`() = runTest {
        val host = FakeHost(backgroundScope)
        val app = FakeApp(holdVpnPreparation = true)
        host.app = app
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))
        val start = machine.requestStart()
        testScheduler.runCurrent()
        backgroundScope.launch { machine.handleVpnStartRequested() }
        testScheduler.runCurrent()
        app.answerPreparation(0, true)
        testScheduler.runCurrent()
        assertEquals(false, host.runtime?.vpn)

        assertTrue(machine.requestStop().await())
        testScheduler.runCurrent()

        assertFalse(start.await())
        assertEquals(1, host.startCalls)
        assertEquals(1, app.cancelledPreparations)
        assertEquals(null, host.runtime)
        assertFalse(machine.vpnDemandedBySystem.value)
        assertEquals(RunState.STOPPED, machine.runState.value)
    }

    @Test
    fun `the start Flutter sends back for Always-on runs as a VPN`() = runTest {
        val host = FakeHost(backgroundScope)
        val tile = FakeTile()
        host.tile = tile
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))

        machine.handleVpnStartRequested()
        machine.requestStart().await()

        assertEquals(1, tile.startCount)
        assertEquals(true, host.lastStartOptions?.enable)
        assertTrue(machine.requestRestart().await())
        assertEquals(true, host.runtime?.vpn)
    }

    @Test
    fun `a stop ends the VPN mode Always-on asked for`() = runTest {
        val host = FakeHost(backgroundScope)
        host.storedSharedState = configuredState(enable = false)
        val machine = ServiceStateMachine(host)
        machine.handleVpnStartRequested()

        machine.requestStop().await()
        machine.requestStart().await()

        assertEquals(false, host.lastStartOptions?.enable)
        assertEquals(false, host.runtime?.vpn)
        assertFalse(machine.vpnDemandedBySystem.value)
    }

    @Test
    fun `a revoke cancels the VPN Always-on asked for before it is up`() = runTest {
        val host = FakeHost(backgroundScope)
        host.tile = FakeTile()
        val machine = ServiceStateMachine(host)
        machine.syncSharedState(configuredState(enable = false))
        machine.handleVpnStartRequested()

        machine.handleVpnRevokeAction()

        assertFalse(machine.requestStart().await())
        assertEquals(0, host.startCalls)
        assertFalse(machine.vpnDemandedBySystem.value)
    }

    @Test
    fun `a revoke keeps a proxy run that Always-on was turning into a VPN`() = runTest {
        for (granted in listOf(true, false)) {
            val host = FakeHost(backgroundScope)
            val machine = ServiceStateMachine(host)
            machine.syncSharedState(configuredState(enable = false))
            machine.requestStart().await()
            val app = FakeApp(holdVpnPreparation = true, holdOnlyVpn = true)
            host.app = app
            backgroundScope.launch { machine.handleVpnStartRequested() }
            testScheduler.runCurrent()

            machine.handleVpnRevokeAction()
            app.answerPreparation(0, granted)
            testScheduler.runCurrent()

            assertFalse(machine.vpnDemandedBySystem.value)
            assertEquals(1, app.cancelledPreparations)
            assertEquals(1, host.startCalls)
            assertEquals(0, host.stopCalls)
            assertEquals(false, host.runtime?.vpn)
            assertEquals(RunState.STARTED, machine.runState.value)
        }
    }

    @Test
    fun `a stopped start still refuses its command after a later handoff is declined`() =
        runTest {
            val host = FakeHost(backgroundScope)
            val tile = FakeTile()
            host.tile = tile
            val machine = ServiceStateMachine(host)
            machine.syncSharedState(configuredState())
            machine.handleStartAction()
            machine.handleStopAction()
            machine.handleStartAction()
            machine.handleStopAction()

            tile.answerLatest()
            testScheduler.runCurrent()

            assertFalse(machine.requestStart().await())
            assertEquals(0, host.startCalls)
            assertFalse(machine.isRunRequested)
        }
}
