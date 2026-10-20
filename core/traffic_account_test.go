package core

import (
	"testing"

	"github.com/metacubex/mihomo/component/proxydialer"
	"github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

// The TUN listener asserts provider.Tunnel unchecked; the wrapper must offer it.
func TestTrafficTunnelOffersEveryInterfaceMihomoAsserts(t *testing.T) {
	if _, ok := trafficTunnel.(provider.Tunnel); !ok {
		t.Fatal("trafficTunnel does not satisfy provider.Tunnel; TUN start panics")
	}
	if _, ok := trafficTunnel.(proxydialer.Tunnel); !ok {
		t.Fatal("trafficTunnel does not satisfy proxydialer.Tunnel")
	}
	rp := trafficTunnel.(provider.Tunnel)
	if rp.RuleUpdateCallback() != tunnel.Tunnel.RuleUpdateCallback() {
		t.Fatal("rule update callback must be mihomo's own, not a fresh one")
	}
}
