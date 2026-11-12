package core

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
)

type gate struct{ ch atomic.Pointer[chan struct{}] }

func openGate(t *testing.T) *gate {
	g := &gate{}
	g.shut(t)()
	return g
}

func (g *gate) wait() { <-*g.ch.Load() }

func (g *gate) shut(t *testing.T) (open func()) {
	ch := make(chan struct{})
	g.ch.Store(&ch)
	open = sync.OnceFunc(func() { close(ch) })
	t.Cleanup(open)
	return open
}

func checkServer(t *testing.T, answers *gate) *httptest.Server {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		answers.wait()
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(server.Close)
	return server
}

// A SOCKS server that hangs up on every connection once fails is open.
func failingSocks(t *testing.T, fails *gate) int {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				fails.wait()
				_ = conn.Close()
			}()
		}
	}()
	return listener.Addr().(*net.TCPAddr).Port
}

func closedPort(t *testing.T) int {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	_ = listener.Close()
	return port
}

// A group of kind over a node behind the SOCKS server on port and a direct one.
func autoGroupProfile(kind string, port int, testURL string) string {
	return fmt.Sprintf(`proxies:
  - {name: dead, type: socks5, server: 127.0.0.1, port: %d}
  - {name: live, type: direct}
proxy-groups:
  - {name: Auto, type: %s, proxies: [dead, live], url: %q}
`, port, kind, testURL)
}

func applyProfile(t *testing.T, profile string, pinned map[string]string) {
	t.Helper()
	if err := os.WriteFile(runningConfigPath(), []byte(profile), 0o600); err != nil {
		t.Fatal(err)
	}
	params := defaultSetupParams()
	params.SelectedMap = pinned
	if err := applyConfig(params); err != nil {
		t.Fatalf("apply: %v", err)
	}
}

func waitFor(t *testing.T, what string, done func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !done() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func autoGroupState(t *testing.T) (now, fixed string) {
	t.Helper()
	group, _, fixed, ok := autoGroupOf(lookupProxy("Auto"))
	if !ok {
		t.Fatal("the group is not running")
	}
	return group.Now(), fixed
}

func liveChecked(testURL string) func() bool {
	return func() bool {
		group, _, _, ok := autoGroupOf(lookupProxy("Auto"))
		return ok && testedFor(memberNamed(group, "live"), testURL)
	}
}

func shortHeldChecks(t *testing.T) {
	previous := heldCheckInterval
	heldCheckInterval = 10 * time.Millisecond
	t.Cleanup(func() {
		selectMu.Lock()
		clear(heldPicks)
		selectMu.Unlock()
		waitFor(t, "the hold watcher to stop", func() bool {
			selectMu.Lock()
			defer selectMu.Unlock()
			return !heldWatching
		})
		heldCheckInterval = previous
	})
}

func expectHeldOnLive(t *testing.T) {
	t.Helper()
	if now, _ := autoGroupState(t); now != "live" {
		t.Fatalf("the reloaded group runs %q before its check, want the live node it ran", now)
	}
	view, _ := handleGetProxies().Proxies["Auto"].(map[string]any)
	if fixed, _ := view["fixed"].(string); fixed != "" {
		t.Errorf("the host sees the held node as a pin of the user's: %q", fixed)
	}
}

func expectReleasedOnLive(t *testing.T) {
	t.Helper()
	waitFor(t, "the hold to end once the nodes were checked", func() bool {
		return len(heldGroups()) == 0
	})
	if now, fixed := autoGroupState(t); now != "live" || fixed != "" {
		t.Errorf("after the check the group runs %q pinned to %q, want live, unpinned", now, fixed)
	}
}

// The url-test group on the live node after its first check, with what the
// next checks answer left to answers.
func runningOnLive(t *testing.T, answers *gate) string {
	server := checkServer(t, answers)
	applyProfile(t, autoGroupProfile("url-test", closedPort(t), server.URL), nil)
	waitFor(t, "the first check", liveChecked(server.URL))
	// mihomo keeps the fastest node it found for ten seconds.
	group, _, _, _ := autoGroupOf(lookupProxy("Auto"))
	group.ForceSet("")
	waitFor(t, "the group to run the live node", func() bool {
		return carriedPicks()["Auto"].proxy == "live"
	})
	return server.URL
}

func TestAnAppliedUrlTestGroupKeepsItsNodeUntilTheNodeIsCheckedAgain(t *testing.T) {
	runningApplies(t)
	shortHeldChecks(t)
	answers := openGate(t)
	testURL := runningOnLive(t, answers)

	answer := answers.shut(t)
	applyProfile(t, autoGroupProfile("url-test", closedPort(t), testURL), nil)
	expectHeldOnLive(t)
	applyProfile(t, autoGroupProfile("url-test", closedPort(t), testURL), nil)
	expectHeldOnLive(t)

	answer()
	expectReleasedOnLive(t)
}

func TestAnAppliedFallbackGroupWaitsForTheNodesBeforeItsOwn(t *testing.T) {
	runningApplies(t)
	shortHeldChecks(t)
	server := checkServer(t, openGate(t))
	fails := openGate(t)

	applyProfile(t, autoGroupProfile("fallback", failingSocks(t, fails), server.URL), nil)
	waitFor(t, "the first check to find the first node dead", func() bool {
		return carriedPicks()["Auto"].proxy == "live"
	})

	fail := fails.shut(t)
	applyProfile(t, autoGroupProfile("fallback", failingSocks(t, fails), server.URL), nil)
	expectHeldOnLive(t)
	waitFor(t, "the held node's check", liveChecked(server.URL))
	time.Sleep(5 * heldCheckInterval)
	if heldGroups()["Auto"] == nil {
		t.Fatal("released while the node before the held one was unchecked")
	}

	fail()
	expectReleasedOnLive(t)
}

// The group running applied again while its checks hang, so the hold stays.
func heldOnLive(t *testing.T) (testURL string, answer func()) {
	shortHeldChecks(t)
	answers := openGate(t)
	testURL = runningOnLive(t, answers)
	answer = answers.shut(t)
	applyProfile(t, autoGroupProfile("url-test", closedPort(t), testURL), nil)
	expectHeldOnLive(t)
	return testURL, answer
}

func TestAPickOfTheUsersEndsTheHold(t *testing.T) {
	runningApplies(t)
	heldOnLive(t)

	if result := handleChangeProxy(&ChangeProxyParams{GroupName: "Auto", ProxyName: "missing"}); result.Message == "" {
		t.Fatal("picked a node the group does not have")
	}
	if heldGroups()["Auto"] == nil {
		t.Fatal("a refused pick ended the hold and left its pin behind")
	}

	if result := handleChangeProxy(&ChangeProxyParams{GroupName: "Auto", ProxyName: "dead"}); result.Message != "" {
		t.Fatalf("pick: %s", result.Message)
	}
	if len(heldGroups()) != 0 {
		t.Fatal("the hold outlived a pick of the user's")
	}
	if _, fixed := autoGroupState(t); fixed != "dead" {
		t.Errorf("the group is pinned to %q, want the user's pick", fixed)
	}
}

func TestAGroupTheUserPinnedIsNotHeld(t *testing.T) {
	runningApplies(t)
	answers := openGate(t)
	testURL := runningOnLive(t, answers)
	answers.shut(t)

	applyProfile(t, autoGroupProfile("url-test", closedPort(t), testURL), map[string]string{"Auto": "dead"})

	if len(heldGroups()) != 0 {
		t.Fatal("held a group the user had pinned")
	}
	if _, fixed := autoGroupState(t); fixed != "dead" {
		t.Errorf("the group is pinned to %q, want the user's pick", fixed)
	}
}

func TestAHoldLeavesTheGroupThatReplacedItsOwnAlone(t *testing.T) {
	runningApplies(t)
	testURL, answer := heldOnLive(t)

	cfg := parsedProfile(t, autoGroupProfile("url-test", closedPort(t), testURL))
	group, _, _, _ := autoGroupOf(cfg.Proxies["Auto"])
	group.ForceSet("live")
	hub.ApplyConfig(mihomoConfig(cfg))
	answer()
	waitFor(t, "the hold to end", func() bool { return len(heldGroups()) == 0 })

	if _, fixed := autoGroupState(t); fixed != "live" {
		t.Errorf("the replacement group is pinned to %q, want the pin it was given", fixed)
	}
}

func TestAnApplyDoesNotHoldOverAPickMadeWhileItRan(t *testing.T) {
	runningApplies(t)
	testURL, _ := heldOnLive(t)
	carried := carriedPicks()

	if result := handleChangeProxy(&ChangeProxyParams{GroupName: "Auto", ProxyName: ""}); result.Message != "" {
		t.Fatalf("unpin: %s", result.Message)
	}
	cfg := parsedProfile(t, autoGroupProfile("url-test", closedPort(t), testURL))
	hub.ApplyConfig(mihomoConfig(cfg))
	holdPicks(cfg.Proxies, carried, nil)

	if len(heldGroups()) != 0 {
		t.Fatal("the apply held the group over the user's pick")
	}
}

func TestAHoldOnANodeTheGroupLostIsLetGo(t *testing.T) {
	runningApplies(t)
	shortHeldChecks(t)
	server := checkServer(t, openGate(t))
	fails := openGate(t)
	fails.shut(t)
	nodes := func(names ...string) string {
		list := "proxies:\n"
		for _, name := range names {
			list += fmt.Sprintf("  - {name: %s, type: socks5, server: 127.0.0.1, port: %d}\n", name, failingSocks(t, fails))
		}
		return list
	}
	provider := filepath.Join(constant.Path.HomeDir(), "sub.yaml")
	if err := os.WriteFile(provider, []byte(nodes("first", "held")), 0o600); err != nil {
		t.Fatal(err)
	}
	applyProfile(t, fmt.Sprintf(`proxy-providers:
  sub: {type: file, path: ./sub.yaml}
proxy-groups:
  - {name: Auto, type: fallback, use: [sub], url: %q}
`, server.URL), nil)
	selectMu.Lock()
	revision := pickRevisions["Auto"]
	selectMu.Unlock()
	holdPicks(allProxies(), map[string]heldPick{"Auto": {proxy: "held", testURL: server.URL, revision: revision}}, nil)
	if heldGroups()["Auto"] == nil {
		t.Fatal("the fallback group was not held")
	}

	running := handleGetExternalProvider("sub")
	if err := handleSideLoadExternalProvider(&SideLoadParams{
		ProviderName: "sub", Path: running.Path, Type: running.Type, Data: nodes("first", "second"),
	}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "the hold to end", func() bool { return len(heldGroups()) == 0 })

	if _, fixed := autoGroupState(t); fixed != "" {
		t.Errorf("the group is left pinned to %q", fixed)
	}
}

func parsedProfile(t *testing.T, profile string) *config.Config {
	t.Helper()
	raw, err := config.UnmarshalRawConfig([]byte(profile))
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	return cfg
}
