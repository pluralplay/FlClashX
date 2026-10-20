package core

import (
	"sync/atomic"

	"github.com/metacubex/mihomo/tunnel/statistic"
)

// Out of the host's sight the connection, DNS and delay streams stop; the tunnel runs on.
var hostActive atomic.Bool

func init() {
	hostActive.Store(true)
}

func hostWantsEvents() bool {
	return hasEventListener() && hostActive.Load()
}

func handleSetHostActive(active bool) bool {
	if hostActive.Swap(active) == active {
		return true
	}
	if !active {
		stopDelayWatch()
		return true
	}
	if isRunning.Load() {
		startDelayWatch()
	}
	statistic.DefaultManager.Range(func(tracker statistic.Tracker) bool {
		watchRequestTraffic(tracker)
		return true
	})
	return true
}
