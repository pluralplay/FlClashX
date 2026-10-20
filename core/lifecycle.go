package core

import (
	"runtime"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

const isAndroid = runtime.GOOS == "android"

var (
	isInit     atomic.Bool
	isRunning  atomic.Bool
	sdkVersion atomic.Int32
)

func handleInitClash(params *InitParams) bool {
	configMu.Lock()
	defer configMu.Unlock()
	sdkVersion.Store(int32(params.Version))
	constant.SetHomeDir(params.HomeDir)
	initOwnership(params.HomeDir)
	clearSpilledResponses()
	isInit.Store(true)
	return true
}

func handleGetIsInit() bool {
	return isInit.Load()
}

// The mihomo release this core was linked with, set by the build's ldflags.
func handleGetCoreVersion() string {
	return constant.Version
}

func handleStartListener() bool {
	configMu.Lock()
	defer configMu.Unlock()
	isRunning.Store(true)
	updateListeners(currentConfig)
	resolver.ResetConnection()
	refreshRoute()
	return true
}

func handleStopListener() bool {
	configMu.Lock()
	defer configMu.Unlock()
	isRunning.Store(false)
	stopListeners()
	resolver.ResetConnection()
	return true
}

// The listeners are the core's own, handed [trafficTunnel]. mihomo's apply
// opens none while the core is stopped (see mihomoConfig) and, while it
// runs, re-creates only what changed; those it created are re-created here
// onto the accounting tunnel, which an unchanged listener keeps.
func updateListeners(cfg *config.Config) {
	if cfg == nil || !isRunning.Load() {
		return
	}
	general := cfg.General
	listener.PatchInboundListeners(cfg.Listeners, trafficTunnel, true)

	listener.SetAllowLan(general.AllowLan)
	inbound.SetSkipAuthPrefixes(general.SkipAuthPrefixes)
	inbound.SetAllowedIPs(general.LanAllowedIPs)
	inbound.SetDisAllowedIPs(general.LanDisAllowedIPs)

	listener.SetBindAddress(general.BindAddress)
	listener.ReCreateHTTP(general.Port, trafficTunnel)
	listener.ReCreateSocks(general.SocksPort, trafficTunnel)
	listener.ReCreateRedir(general.RedirPort, trafficTunnel)
	listener.ReCreateTProxy(general.TProxyPort, trafficTunnel)
	listener.ReCreateMixed(general.MixedPort, trafficTunnel)
	listener.ReCreateShadowSocks(general.ShadowSocksConfig, trafficTunnel)
	listener.ReCreateVmess(general.VmessConfig, trafficTunnel)
	listener.ReCreateTuic(general.TuicServer, trafficTunnel)
	if !isAndroid {
		listener.ReCreateTun(general.Tun, trafficTunnel)
	}
}

// mihomo closes a listener re-created with nothing to listen on.
func stopListeners() {
	listener.PatchInboundListeners(nil, trafficTunnel, true)
	listener.ReCreateHTTP(0, trafficTunnel)
	listener.ReCreateSocks(0, trafficTunnel)
	listener.ReCreateRedir(0, trafficTunnel)
	listener.ReCreateTProxy(0, trafficTunnel)
	listener.ReCreateMixed(0, trafficTunnel)
	listener.ReCreateShadowSocks("", trafficTunnel)
	listener.ReCreateVmess("", trafficTunnel)
	listener.ReCreateTuic(LC.TuicServer{}, trafficTunnel)
	if !isAndroid {
		listener.ReCreateTun(LC.Tun{}, trafficTunnel)
	}
}

func handleShutdown() bool {
	handleStopLog()
	stopRouteWatch()

	configMu.Lock()
	isRunning.Store(false)
	stopListeners()
	stopGeoUpdater()
	stopDelayWatch()
	executor.Shutdown()
	currentConfig = nil
	isInit.Store(false)
	configMu.Unlock()

	handleForceGC()
	return true
}

func handleForceGC() {
	invalidateAllProxies()
	debug.FreeOSMemory()
}

// mihomo loads providers without waiting for them, so its own GC misses their decode buffers.
var (
	loadReleaseDelay  = 2 * time.Second
	releaseLoadMemory = debug.FreeOSMemory

	loadReleaseMu    sync.Mutex
	loadReleaseTimer *time.Timer
)

func scheduleLoadMemoryRelease() {
	loadReleaseMu.Lock()
	defer loadReleaseMu.Unlock()
	if loadReleaseTimer == nil {
		loadReleaseTimer = time.AfterFunc(loadReleaseDelay, func() { releaseLoadMemory() })
		return
	}
	loadReleaseTimer.Reset(loadReleaseDelay)
}

// HeapIdle still counts spans the runtime has already handed back to the OS,
// so the retained-but-unused figure subtracts HeapReleased.
func handleGetMemoryStats() MemoryStats {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return MemoryStats{
		Rss:          statistic.DefaultManager.Memory(),
		HeapInuse:    stats.HeapInuse,
		HeapIdle:     stats.HeapIdle - stats.HeapReleased,
		StackInuse:   stats.StackInuse,
		RuntimeOther: stats.MSpanInuse + stats.MCacheInuse + stats.BuckHashSys + stats.GCSys + stats.OtherSys,
	}
}
