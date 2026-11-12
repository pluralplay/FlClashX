//go:build !android

package core

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/tproxy"
)

// sing-tun's Linux policy routes outlive the process; the Helper kills a Core still
// running 3 s after its SIGTERM, which leaves the fallback below a second of its own.
var exitCleanupTimeout = 2 * time.Second

// An apply holds configMu while mihomo waits on provider downloads, so the
// routes and iptables rules are then torn down without it.
var releaseHostNetwork = func() {
	tproxy.CleanupTProxyIPTables()
	listener.ReCreateTun(LC.Tun{}, trafficTunnel)
}

func releaseOnExit() {
	if !isInit.Load() {
		return
	}
	isRunning.Store(false)
	done := make(chan struct{})
	go func() {
		defer close(done)
		handleShutdown()
	}()
	select {
	case <-done:
	case <-time.After(exitCleanupTimeout):
		releaseHostNetwork()
		fmt.Fprintln(os.Stderr, "[ERROR] core cleanup did not finish before exit")
	}
}

func ExitOnTermination() {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	<-signals
	releaseOnExit()
	os.Exit(0)
}
