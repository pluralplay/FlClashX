package core

import (
	"strings"
	"sync"

	"github.com/metacubex/mihomo/config"
)

// Profile text mihomo drops: `serverDescription` on a proxy, `groupDescription`
// on a group; captured at every load, served with the proxies.
var (
	descriptionsMu sync.RWMutex
	descriptions   = map[string]string{}
)

var proxyDescriptionKeys = []string{"serverDescription", "server-description"}

var groupDescriptionKeys = []string{"groupDescription"}

func captureDescriptions(raw *config.RawConfig) {
	next := make(map[string]string)
	collect := func(items []map[string]any, keys []string) {
		for _, item := range items {
			name, _ := item["name"].(string)
			if name == "" {
				continue
			}
			for _, key := range keys {
				if text, ok := item[key].(string); ok && strings.TrimSpace(text) != "" {
					next[name] = strings.TrimSpace(text)
					break
				}
			}
		}
	}
	collect(raw.Proxy, proxyDescriptionKeys)
	collect(raw.ProxyGroup, groupDescriptionKeys)
	descriptionsMu.Lock()
	descriptions = next
	descriptionsMu.Unlock()
}

func descriptionOf(name string) string {
	descriptionsMu.RLock()
	defer descriptionsMu.RUnlock()
	return descriptions[name]
}
