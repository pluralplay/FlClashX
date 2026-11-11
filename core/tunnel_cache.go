package core

import (
	"reflect"
	"sync"

	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

// Every proxy the tunnel can route to, the declared ones and the ones its
// providers carry, keyed by name. Rebuilding costs one entry per proxy, on
// a large subscription megabytes of garbage per call, so the answer is kept
// until an apply swaps the tunnel's maps or a provider bumps its version.
var proxyCache struct {
	sync.Mutex
	proxies   map[string]constant.Proxy
	base      uintptr
	providers uintptr
	versions  map[string]uint32
}

func allProxies() map[string]constant.Proxy {
	base := tunnel.Proxies()
	providers := tunnel.Providers()
	proxyCache.Lock()
	defer proxyCache.Unlock()
	if proxyCache.proxies != nil &&
		proxyCache.base == mapIdentity(base) &&
		proxyCache.providers == mapIdentity(providers) &&
		proxyCacheUpToDate(providers) {
		return proxyCache.proxies
	}
	rebuilt := make(map[string]constant.Proxy, len(base))
	for name, proxy := range base {
		rebuilt[name] = proxy
	}
	versions := make(map[string]uint32, len(providers))
	for name, p := range providers {
		// Version before proxies: the other order can stamp a version newer
		// than the list that was read, and the cache never recovers.
		versions[name] = p.Version()
		for _, proxy := range p.Proxies() {
			rebuilt[proxy.Name()] = proxy
		}
	}
	proxyCache.proxies = rebuilt
	proxyCache.base = mapIdentity(base)
	proxyCache.providers = mapIdentity(providers)
	proxyCache.versions = versions
	return rebuilt
}

func mapIdentity(m any) uintptr {
	value := reflect.ValueOf(m)
	if value.IsNil() {
		return 0
	}
	return value.Pointer()
}

func proxyCacheUpToDate(providers map[string]cp.ProxyProvider) bool {
	if len(providers) != len(proxyCache.versions) {
		return false
	}
	for name, p := range providers {
		version, tracked := proxyCache.versions[name]
		if !tracked || version != p.Version() {
			return false
		}
	}
	return true
}

// For a host that would rather pay for one rebuild than keep the map
// resident: the cache is the last reference to the proxies a provider
// already replaced.
func invalidateAllProxies() {
	proxyCache.Lock()
	defer proxyCache.Unlock()
	proxyCache.proxies = nil
	proxyCache.versions = nil
}

func providersSnapshot() map[string]cp.ProxyProvider {
	return tunnel.Providers()
}

func ruleProvidersSnapshot() map[string]cp.RuleProvider {
	return tunnel.RuleProviders()
}
