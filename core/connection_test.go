package core

import (
	"io"
	"net"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func TestProxyOnlyTrafficLeavesOutADirectProxyOfAnyName(t *testing.T) {
	direct := outbound.NewDirectWithOption(outbound.DirectOption{Name: "直连"})
	reject := outbound.NewRejectWithOption(outbound.RejectOption{Name: "HK"})
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"直连": adapter.NewProxy(direct),
		"HK": adapter.NewProxy(reject),
	}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	for _, test := range []struct {
		outbound constant.ProxyAdapter
		proxied  int64
	}{
		{direct, 0},
		{reject, 5},
	} {
		handleResetTraffic()
		local, remote := net.Pipe()
		go func() { _, _ = io.Copy(io.Discard, remote) }()
		metadata := &constant.Metadata{}
		tracker := statistic.NewTCPTracker(
			outbound.NewConn(local, test.outbound),
			statistic.DefaultManager,
			metadata,
			nil,
			0,
			0,
			true,
		)
		// The accounting tunnel wraps the inbound side; here the tracker
		// stands in for it, so the bytes count as sent back to the client.
		inbound := &accountedConn{Conn: tracker, metadata: metadata}

		if _, err := inbound.Write([]byte("hello")); err != nil {
			t.Fatalf("write through %s: %v", test.outbound.Name(), err)
		}
		_ = tracker.Close()
		_ = remote.Close()

		all := handleGetTotalTraffic(false)
		proxied := handleGetTotalTraffic(true)
		if all.Up != 5 || proxied.Down != test.proxied {
			t.Errorf("%s: total %d, proxied %d; want 5 and %d", test.outbound.Name(), all.Up, proxied.Down, test.proxied)
		}
	}
	handleResetTraffic()
}

func TestStoppingClosesTheConnectionsAlreadyOpen(t *testing.T) {
	local, remote := net.Pipe()
	t.Cleanup(func() { _ = remote.Close() })
	go func() { _, _ = io.Copy(io.Discard, remote) }()
	direct := outbound.NewDirectWithOption(outbound.DirectOption{Name: "DIRECT"})
	tracker := statistic.NewTCPTracker(
		outbound.NewConn(local, direct),
		statistic.DefaultManager,
		&constant.Metadata{},
		nil,
		0,
		0,
		true,
	)
	id := tracker.ID()
	if statistic.DefaultManager.Get(id) == nil {
		t.Fatal("the connection was not tracked")
	}

	handleStopListener()

	if statistic.DefaultManager.Get(id) != nil {
		t.Error("the connection outlived the stop")
	}
	if _, err := local.Write([]byte("x")); err == nil {
		t.Error("the connection still carries traffic after the stop")
	}
}
