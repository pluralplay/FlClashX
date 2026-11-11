package core

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/inner"
	"github.com/metacubex/mihomo/log"
)

// freeLoopbackPorts holds every probe open until all are taken, so no two match.
func freeLoopbackPorts(t *testing.T, count int) []int {
	t.Helper()
	ports := make([]int, count)
	for index := range ports {
		probe, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatalf("listen: %v", err)
		}
		defer probe.Close()
		ports[index] = probe.Addr().(*net.TCPAddr).Port
	}
	return ports
}

func loopback(port int) string {
	return net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
}

func accepts(address string) bool {
	conn, err := net.DialTimeout("tcp", address, time.Second)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func stopAfter(t *testing.T) {
	t.Cleanup(func() {
		isRunning.Store(false)
		stopListeners()
	})
}

func TestForwardingTunnelsListenOnlyWhileRunning(t *testing.T) {
	address := loopback(freeLoopbackPorts(t, 1)[0])
	cfg := &config.Config{
		General: &config.General{Inbound: config.Inbound{BindAddress: "*"}},
		Tunnels: []LC.Tunnel{{Network: []string{"tcp"}, Address: address, Target: "127.0.0.1:9", Proxy: "DIRECT"}},
	}
	withCurrentConfig(t, cfg)
	stopAfter(t)

	if handed := mihomoConfig(cfg).Tunnels; len(handed) != 0 {
		t.Fatalf("a stopped core handed mihomo's apply the tunnels %v", handed)
	}
	handleStartListener()
	if !accepts(address) {
		t.Fatal("the tunnel does not listen once the core runs")
	}
	handleStopListener()
	if accepts(address) {
		t.Error("the tunnel still listens after the core stopped")
	}
}

func mixedConfig(t *testing.T, port int) *config.Config {
	t.Helper()
	return parsedConfig(t, func(raw *config.RawConfig) { raw.MixedPort = port })
}

func parsedConfig(t *testing.T, edit func(*config.RawConfig)) *config.Config {
	t.Helper()
	raw := config.DefaultRawConfig()
	raw.Profile.StoreSelected = false
	edit(raw)
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return cfg
}

// socksConnect opens a SOCKS5 CONNECT to target through the proxy at port.
func socksConnect(t *testing.T, port int, target net.Addr) net.Conn {
	t.Helper()
	conn, err := net.DialTimeout("tcp", loopback(port), time.Second)
	if err != nil {
		t.Fatalf("dial the proxy: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	tcp := target.(*net.TCPAddr)
	request := []byte{5, 1, 0, 5, 1, 0, 1}
	request = append(request, tcp.IP.To4()...)
	request = binary.BigEndian.AppendUint16(request, uint16(tcp.Port))
	if _, err := conn.Write(request); err != nil {
		t.Fatalf("write the handshake: %v", err)
	}
	reply := make([]byte, 12)
	if _, err := io.ReadFull(conn, reply); err != nil {
		t.Fatalf("read the handshake: %v", err)
	}
	if reply[3] != 0 {
		t.Fatalf("CONNECT answered %d", reply[3])
	}
	return conn
}

func waitAccounted(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		found := false
		openInbound.Range(func(any, any) bool {
			found = true
			return false
		})
		if found {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("the connection never reached the accounting tunnel")
}

func recreatedListeners(apply func()) []string {
	subscription := log.Subscribe()
	defer log.UnSubscribe(subscription)
	apply()
	var opened []string
	for {
		select {
		case event := <-subscription:
			if strings.Contains(event.Payload, "listening at") {
				opened = append(opened, event.Payload)
			}
		case <-time.After(200 * time.Millisecond):
			return opened
		}
	}
}

// runningApplies lets a test call mihomo's real apply, which leaves the
// inner tunnel set for every HTTP download the tests after it make.
func runningApplies(t *testing.T) {
	previous, innerTunnel := constant.Path.HomeDir(), inner.GetTunnel()
	constant.SetHomeDir(t.TempDir())
	t.Cleanup(func() {
		constant.SetHomeDir(previous)
		inner.New(innerTunnel)
	})
	isRunning.Store(true)
	stopAfter(t)
}

func TestApplyLeavesEveryListenerOnTheAccountingTunnel(t *testing.T) {
	runningApplies(t)
	ports := freeLoopbackPorts(t, 2)
	before, after := ports[0], ports[1]
	updateListeners(mixedConfig(t, before))

	moved := mixedConfig(t, after)
	hub.ApplyConfig(mihomoConfig(moved))
	if got := listener.GetPorts().MixedPort; got != before {
		t.Fatalf("mihomo's apply moved the mixed port to %d itself", got)
	}
	updateListeners(moved)
	if got := listener.GetPorts().MixedPort; got != after {
		t.Fatalf("mixed port = %d, want %d", got, after)
	}
	socksConnect(t, after, blackHoleServer(t))
	waitAccounted(t)

	if reopened := recreatedListeners(func() {
		hub.ApplyConfig(mihomoConfig(moved))
		updateListeners(moved)
	}); len(reopened) != 0 {
		t.Errorf("a reload with the same ports re-created %v", reopened)
	}
}

func TestApplyDoesNotRetryWhatTheCoreFailedToOpen(t *testing.T) {
	runningApplies(t)
	ports := freeLoopbackPorts(t, 2)
	forward, named := loopback(ports[0]), loopback(ports[1])
	cfg := parsedConfig(t, func(raw *config.RawConfig) {
		raw.Tunnels = []LC.Tunnel{{Network: []string{"tcp"}, Address: forward, Target: "127.0.0.1:9", Proxy: "DIRECT"}}
		raw.Listeners = []map[string]any{{"name": "named", "type": "mixed", "listen": "127.0.0.1", "port": ports[1]}}
	})
	var held []net.Listener
	for _, address := range []string{forward, named} {
		occupant, err := net.Listen("tcp", address)
		if err != nil {
			t.Fatalf("occupy %s: %v", address, err)
		}
		held = append(held, occupant)
	}
	updateListeners(cfg)
	for _, occupant := range held {
		_ = occupant.Close()
	}

	hub.ApplyConfig(mihomoConfig(cfg))
	for _, address := range []string{forward, named} {
		if accepts(address) {
			t.Errorf("mihomo's apply opened %s, which the core failed to", address)
		}
	}
	updateListeners(cfg)
	for _, address := range []string{forward, named} {
		if !accepts(address) {
			t.Errorf("the core did not open %s once it was free", address)
		}
	}
}

func TestIPTablesAreLeftOutOfMihomosApply(t *testing.T) {
	cfg := parsedConfig(t, func(raw *config.RawConfig) {
		raw.IPTables.Enable, raw.IPTables.DnsRedirect = true, false
		raw.TProxyPort = 7895
	})

	if mihomoConfig(cfg).IPTables.Enable {
		t.Fatal("mihomo's apply was handed iptables, which it sets for the ports open before")
	}
	if !cfg.IPTables.Enable {
		t.Fatal("handing mihomo's apply a config turned the requested iptables off")
	}
	rules, err := ipTablesRulesOf(cfg)
	if err != nil || rules.tproxyPort != 7895 || rules.inboundInterface != "lo" {
		t.Errorf("rules = %+v, %v; want the requested tproxy port 7895 on lo", rules, err)
	}
	cfg.General.Tun.Enable = true
	if _, err := ipTablesRulesOf(cfg); err == nil {
		t.Error("iptables were allowed alongside the TUN")
	}
}

func TestStopClosesTheListenersAControllerReloadOpened(t *testing.T) {
	ports := freeLoopbackPorts(t, 2)
	forward, named := loopback(ports[0]), loopback(ports[1])
	cfg := parsedConfig(t, func(raw *config.RawConfig) {
		raw.Tunnels = []LC.Tunnel{{Network: []string{"tcp"}, Address: forward, Target: "127.0.0.1:9", Proxy: "DIRECT"}}
		raw.Listeners = []map[string]any{{"name": "reloaded", "type": "mixed", "listen": "127.0.0.1", "port": ports[1]}}
	})
	listener.PatchInboundListeners(cfg.Listeners, trafficTunnel, true)
	listener.PatchTunnel(cfg.Tunnels, trafficTunnel)
	t.Cleanup(func() {
		listener.PatchInboundListeners(nil, trafficTunnel, true)
		listener.PatchTunnel(nil, trafficTunnel)
	})

	stopListeners()
	for _, address := range []string{forward, named} {
		if accepts(address) {
			t.Errorf("%s still listens after Stop", address)
		}
	}
}

func TestANamedListenerThatFailsPartwayClosesWhatItOpened(t *testing.T) {
	ports := freeLoopbackPorts(t, 2)
	slices.Sort(ports)
	occupant, err := net.Listen("tcp", loopback(ports[1]))
	if err != nil {
		t.Fatalf("occupy: %v", err)
	}
	defer occupant.Close()
	cfg := parsedConfig(t, func(raw *config.RawConfig) {
		raw.Listeners = []map[string]any{{
			"name": "split", "type": "http", "listen": "127.0.0.1", "port": fmt.Sprintf("%d,%d", ports[0], ports[1]),
		}}
	})
	t.Cleanup(func() { patchNamedListeners(nil) })

	patchNamedListeners(cfg.Listeners)
	if accepts(loopback(ports[0])) {
		t.Error("the listener kept the port it opened before failing on the next")
	}
}

func TestAFailedIPTablesSetupTakesBackItsRoutingMark(t *testing.T) {
	previous := dialer.DefaultRoutingMark.Load()
	t.Cleanup(func() { dialer.DefaultRoutingMark.Store(previous) })
	fails := func(string, []string, uint16, bool, uint16) error { return errors.New("no iptables") }
	rules := ipTablesRules{inboundInterface: "lo", tproxyPort: 7895}

	dialer.DefaultRoutingMark.Store(0)
	if installIPTables(rules, fails) == nil {
		t.Fatal("a failed setup reported success")
	}
	if mark := dialer.DefaultRoutingMark.Load(); mark != 0 {
		t.Errorf("mark = %d after a failed setup, want it back at 0", mark)
	}
	dialer.DefaultRoutingMark.Store(7)
	_ = installIPTables(rules, fails)
	if mark := dialer.DefaultRoutingMark.Load(); mark != 7 {
		t.Errorf("mark = %d, want the configured 7 kept", mark)
	}
	dialer.DefaultRoutingMark.Store(0)
	_ = installIPTables(rules, func(string, []string, uint16, bool, uint16) error { return nil })
	if mark := dialer.DefaultRoutingMark.Load(); mark != 2158 {
		t.Errorf("mark = %d after setup, want 2158", mark)
	}
}
