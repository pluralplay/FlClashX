//go:build android

package core

import (
	"core/platform"
	t "core/tun"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/log"
)

var (
	eventListenerLock sync.RWMutex
	eventListener     func([]byte)
	listening         atomic.Bool
)

func (th *TunHandler) handleResolveProcess(source, target net.Addr) (int, string) {
	th.mu.RLock()
	defer th.mu.RUnlock()

	if th.callbacks == nil {
		return -1, ""
	}
	var protocol int
	switch source.Network() {
	case "udp", "udp4", "udp6":
		protocol = syscall.IPPROTO_UDP
	case "tcp", "tcp4", "tcp6":
		protocol = syscall.IPPROTO_TCP
	}
	var uid int
	if sdkVersion.Load() < 29 {
		uid = platform.QuerySocketUidFromProcFs(source, target)
	} else {
		uid = th.callbacks.ResolveUid(protocol, source.String(), target.String())
	}
	if uid < 0 {
		return -1, ""
	}
	return uid, th.callbacks.ResolvePackage(uid)
}

var installHooksOnce sync.Once

func installHooks() {
	installHooksOnce.Do(func() {
		dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
			if platform.ShouldBlockConnection() {
				return errBlocked
			}
			th := activeTunHandler.Load()
			if th == nil {
				return nil
			}
			// A refused protect never fails the dial: mihomo's tunnel retries a failed
			// dial ten times, and Android refuses only after the VPN was revoked, when the
			// routes are gone and an unprotected socket takes the default network.
			return conn.Control(func(fd uintptr) {
				protectFrom(th, int(fd))
			})
		}
		process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) {
			th := activeTunHandler.Load()
			if th == nil {
				return "", process.ErrInvalidNetwork
			}
			src, dst := metadata.RawSrcAddr, metadata.RawDstAddr
			if src == nil || dst == nil {
				return "", process.ErrInvalidNetwork
			}
			// Everywhere else mihomo fills Uid from its own procfs lookup, the one Android took away.
			uid, packageName := th.handleResolveProcess(src, dst)
			if uid >= 0 {
				metadata.Uid = uint32(uid)
			}
			return packageName, nil
		}
	})
}

var errBlocked = errors.New("blocked: the process is out of file descriptors")

// Android has the routes up regardless, so a false here must tear the VPN down.
func handleStartTun(callbacks TunCallbacks, fd int, stack, address, dns, options string) bool {
	tunLock.Lock()
	defer tunLock.Unlock()
	if fd == 0 {
		stopTunLocked()
		logError("startTun was handed no tun descriptor")
		return false
	}
	installHooks()
	return startTunLocked(callbacks, func() io.Closer {
		listener := t.Start(fd, stack, address, dns, options, trafficTunnel)
		if listener == nil {
			return nil
		}
		log.Infoln("TUN address: %v", listener.Address())
		return listener
	})
}

var (
	dnsUpdateMu  sync.Mutex
	dnsUpdateSeq atomic.Uint64
)

func handleUpdateDns(value string) {
	// mihomo turns the [""] that Split returns for no servers into a "udp://:"
	// nameserver, which keeps the system resolver off its default fallback.
	var addr []string
	if value != "" {
		addr = strings.Split(value, ",")
	}
	seq := dnsUpdateSeq.Add(1)
	safeGo("updateDns", func() {
		dnsUpdateMu.Lock()
		defer dnsUpdateMu.Unlock()
		if seq != dnsUpdateSeq.Load() {
			return
		}
		log.Infoln("[DNS] updateDns %s", value)
		dns.UpdateSystemDNS(addr)
		resolver.ClearCache()
		resolver.ResetConnection()
	})
}

func init() {
	registerMethod(updateDnsMethod, withArguments(func(value string) bool {
		handleUpdateDns(value)
		return true
	}))
}

// gobind runs an export on the caller's thread and turns no panic into a Java
// exception, so a panic that leaves one ends the whole application.
func recoverExport(name string) {
	if r := recover(); r != nil {
		logError("panic in %s: %v\n%s", name, r, stackTrace())
	}
}

func InvokeMethod(data string, reply func([]byte)) {
	defer recoverExport("invokeMethod")
	call := &MethodCall{}
	if err := json.Unmarshal([]byte(data), call); err != nil {
		reply(encodeResponse(MethodResponse{Error: &MethodError{
			Code:    "invalid_method_call",
			Message: err.Error(),
		}}))
		return
	}
	dispatchMethodCall(call, reply)
}

func StartTun(callbacks TunCallbacks, fd int, stack, address, dns, options string) bool {
	defer recoverExport("startTun")
	started := handleStartTun(callbacks, fd, stack, address, dns, options)
	if !started {
		return false
	}
	if !isRunning.Load() {
		handleStartListener()
	} else {
		handleResetConnections()
		bumpRouteEpoch()
	}
	return true
}

func QuickSetup(initParamsString, setupParamsString string, answer func(string)) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				logError("panic in quickSetup: %v\n%s", r, stackTrace())
				answer(fmt.Sprintf("internal panic: %v", r))
			}
		}()
		initParams := InitParams{}
		if err := json.Unmarshal([]byte(initParamsString), &initParams); err != nil {
			answer("init failed")
			return
		}
		handleInitClash(&initParams)
		setupParams := &SetupParams{}
		if err := json.Unmarshal([]byte(setupParamsString), setupParams); err != nil {
			answer(err.Error())
			return
		}
		isRunning.Store(true)
		if err := handleSetupConfig(setupParams); err != nil {
			answer(err.Error())
			return
		}
		answer("")
	}()
}

// The listener goes away with the Flutter engine, which never gets to release
// the route watch it held, while the service and this core run on.
func SetEventListener(listener func([]byte)) {
	defer recoverExport("setEventListener")
	eventListenerLock.Lock()
	eventListener = listener
	listening.Store(listener != nil)
	eventListenerLock.Unlock()
	if listener == nil {
		stopRouteWatch()
	}
}

func hasEventListener() bool {
	return listening.Load()
}

func deliverEvent(data []byte) {
	eventListenerLock.RLock()
	defer eventListenerLock.RUnlock()
	if eventListener == nil {
		return
	}
	eventListener(data)
}

func StopTun() {
	defer recoverExport("stopTun")
	handleStopTun()
	if isRunning.Load() {
		handleStopListener()
	}
}

func StartListener() {
	defer recoverExport("startListener")
	if !isRunning.Load() {
		handleStartListener()
	}
}

func StopListener() {
	defer recoverExport("stopListener")
	if isRunning.Load() {
		handleStopListener()
	}
}

var forceGCPending atomic.Bool

// Android calls this from onLowMemory and onTrimMemory on the main thread, which
// the Flutter UI shares, and a full collection of a large profile spans frames.
func ForceGC() {
	defer recoverExport("forceGC")
	if !forceGCPending.CompareAndSwap(false, true) {
		return
	}
	safeGo("forceGC", func() {
		defer forceGCPending.Store(false)
		handleForceGC()
	})
}

func UpdateDns(value string) {
	defer recoverExport("updateDns")
	handleUpdateDns(value)
}

func ResetNetwork() {
	defer recoverExport("resetNetwork")
	safeGo("resetNetwork", handleResetNetwork)
}
