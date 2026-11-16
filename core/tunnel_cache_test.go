package core

import (
	"testing"

	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

func compatibleProvider(t *testing.T, name string, proxies ...constant.Proxy) cp.ProxyProvider {
	t.Helper()
	health := provider.NewHealthCheck(proxies, "", 0, 0, true, nil)
	pd, err := provider.NewCompatibleProvider(name, proxies, health)
	if err != nil {
		t.Fatalf("NewCompatibleProvider: %v", err)
	}
	return pd
}

func TestANameAProviderSharesWithADeclaredProxyAlwaysFindsTheProvidersNode(t *testing.T) {
	declared := namedProxy("Proxy")
	node := namedProxy("Proxy")
	tunnel.UpdateProxies(
		map[string]constant.Proxy{"Proxy": declared},
		map[string]cp.ProxyProvider{
			provider.ReservedName: compatibleProvider(t, provider.ReservedName, declared),
			"PP":                  compatibleProvider(t, "PP", node),
		},
	)
	t.Cleanup(func() {
		tunnel.UpdateProxies(nil, nil)
		invalidateAllProxies()
	})

	for rebuild := 0; rebuild < 64; rebuild++ {
		invalidateAllProxies()
		if lookupProxy("Proxy") != node {
			t.Fatalf("rebuild %d found the declared proxy, want the provider's node", rebuild)
		}
	}
}
