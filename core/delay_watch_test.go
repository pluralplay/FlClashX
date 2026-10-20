package core

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

func urlTest(t *testing.T, proxy constant.Proxy, url string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), defaultDelayTestTimeout)
	defer cancel()
	_, _ = proxy.URLTest(ctx, url, anyDelayTestStatus)
}

// mihomo measures whole milliseconds and reads a zero as a failed check, so
// the server must take at least one.
func noContentAfterAMillisecond(w http.ResponseWriter, _ *http.Request) {
	time.Sleep(2 * time.Millisecond)
	w.WriteHeader(http.StatusNoContent)
}

func TestDelayWatchReportsEachHistoryRecordOnce(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	proxy := namedProxy("node")
	proxies := map[string]constant.Proxy{"node": proxy}
	watch := &delayWatch{}

	if got := watch.collect(proxies); len(got) != 0 {
		t.Fatalf("collect before any test = %+v, want nothing", got)
	}
	urlTest(t, proxy, server.URL)
	got := watch.collect(proxies)
	if len(got) != 1 || got[0].Name != "node" || got[0].Url != server.URL || got[0].Value <= 0 {
		t.Fatalf("collect after a test = %d results, first %+v, want one positive delay for node", len(got), got)
	}
	if got := watch.collect(proxies); len(got) != 0 {
		t.Fatalf("collect without a new test = %+v, want nothing", got)
	}
	urlTest(t, proxy, server.URL)
	if got := watch.collect(proxies); len(got) != 1 {
		t.Fatalf("collect after a second test = %+v, want one delay", got)
	}
}

func TestDelayWatchReportsAFailedCheckAsTimeout(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	url := server.URL
	server.Close()
	proxy := namedProxy("node")
	proxies := map[string]constant.Proxy{"node": proxy}
	watch := &delayWatch{}

	urlTest(t, proxy, url)
	got := watch.collect(proxies)
	if len(got) != 1 || got[0].Value != delayTimedOut {
		t.Fatalf("collect after a failed test = %+v, want value %d", got, delayTimedOut)
	}
}

func TestDelayWatchSkipsGroups(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	group := selectorGroup(t, "GROUP", "node")
	proxies := map[string]constant.Proxy{"GROUP": group}
	watch := &delayWatch{}

	urlTest(t, group, server.URL)
	if got := watch.collect(proxies); len(got) != 0 {
		t.Fatalf("collect for a group = %+v, want nothing", got)
	}
}

func TestDelayWatchSlowsDownWhileNothingArrives(t *testing.T) {
	start := time.Now()
	watch := &delayWatch{}
	watch.reset(start)
	if got := watch.interval(start); got != delayWatchFastInterval {
		t.Fatalf("interval right after start = %v, want %v", got, delayWatchFastInterval)
	}
	if got := watch.interval(start.Add(delayWatchQuietAfter)); got != delayWatchSlowInterval {
		t.Fatalf("interval after a quiet spell = %v, want %v", got, delayWatchSlowInterval)
	}
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	proxy := namedProxy("node")
	urlTest(t, proxy, server.URL)
	watch.collect(map[string]constant.Proxy{"node": proxy})
	if got := watch.interval(time.Now()); got != delayWatchFastInterval {
		t.Fatalf("interval after a new record = %v, want %v", got, delayWatchFastInterval)
	}
}
