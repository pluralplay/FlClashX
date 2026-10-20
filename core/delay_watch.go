package core

import (
	"context"
	"sync"
	"time"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// mihomo keeps the result of every check it runs in the proxy's history and
// tells nobody; a patched mihomo used to call a hook. The release's histories
// are read instead, often while records arrive and seldom once they stop.
const (
	delayWatchFastInterval = time.Second
	delayWatchSlowInterval = 5 * time.Second
	delayWatchQuietAfter   = 10 * time.Second
)

type delayRecordKey struct {
	name, url string
}

type delayWatch struct {
	mu         sync.Mutex
	seen       map[delayRecordKey]time.Time
	lastChange time.Time
	cancel     context.CancelFunc
}

var delayWatcher delayWatch

func startDelayWatch() {
	stopDelayWatch()
	if !hostActive.Load() {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	delayWatcher.reset(time.Now())
	delayWatcher.mu.Lock()
	delayWatcher.cancel = cancel
	delayWatcher.mu.Unlock()
	go delayWatcher.run(ctx)
}

func (w *delayWatch) reset(now time.Time) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.lastChange = now
}

func (w *delayWatch) interval(now time.Time) time.Duration {
	w.mu.Lock()
	defer w.mu.Unlock()
	if now.Sub(w.lastChange) < delayWatchQuietAfter {
		return delayWatchFastInterval
	}
	return delayWatchSlowInterval
}

func stopDelayWatch() {
	delayWatcher.mu.Lock()
	defer delayWatcher.mu.Unlock()
	if delayWatcher.cancel != nil {
		delayWatcher.cancel()
		delayWatcher.cancel = nil
	}
}

// A lazy check skips its tick on an idle tunnel; a touch lets the first run.
func touchProviders() {
	for _, provider := range tunnel.Providers() {
		provider.Touch()
	}
}

func (w *delayWatch) run(ctx context.Context) {
	timer := time.NewTimer(w.interval(time.Now()))
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			for _, delay := range w.collect(allProxies()) {
				sendMessage(DelayMessage, delay)
			}
			timer.Reset(w.interval(time.Now()))
		}
	}
}

func (w *delayWatch) collect(proxies map[string]constant.Proxy) []*Delay {
	w.mu.Lock()
	defer w.mu.Unlock()
	live := make(map[delayRecordKey]time.Time, len(w.seen))
	var delays []*Delay
	for name, proxy := range proxies {
		if isProxyGroupType(proxy.Type()) {
			continue
		}
		for url, state := range proxy.ExtraDelayHistories() {
			if len(state.History) == 0 {
				continue
			}
			last := state.History[len(state.History)-1]
			key := delayRecordKey{name: name, url: url}
			live[key] = last.Time
			if previous, ok := w.seen[key]; ok && !last.Time.After(previous) {
				continue
			}
			delays = append(delays, &Delay{Url: url, Name: name, Value: delayValue(last.Delay, true)})
		}
	}
	w.seen = live
	if len(delays) > 0 {
		w.lastChange = time.Now()
	}
	return delays
}
