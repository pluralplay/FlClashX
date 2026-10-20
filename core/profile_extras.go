package core

import (
	"sync"
	"time"

	"github.com/metacubex/mihomo/config"
)

// What the core keeps of a profile beyond what mihomo parses out of it:
// the order its proxies came in, what it says about them, and the dialer
// chains that would loop. The test URL goes in the other way, onto every
// group and provider that names none, which is where mihomo reads it.
func captureProfileExtras(raw *config.RawConfig) {
	captureDescriptions(raw)
	captureProxyOrder(raw)
	injectTestURL(raw)
	for _, name := range dialerLoopsOf(raw) {
		reportDialerLoop(name)
	}
}

var proxyOrder struct {
	sync.RWMutex
	names []string
}

func captureProxyOrder(raw *config.RawConfig) {
	names := make([]string, 0, len(raw.Proxy)+len(raw.ProxyGroup))
	for _, item := range append(append([]map[string]any{}, raw.Proxy...), raw.ProxyGroup...) {
		if name, ok := item["name"].(string); ok && name != "" {
			names = append(names, name)
		}
	}
	proxyOrder.Lock()
	proxyOrder.names = names
	proxyOrder.Unlock()
}

func profileProxyNames() []string {
	proxyOrder.RLock()
	defer proxyOrder.RUnlock()
	return proxyOrder.names
}

// Blanks take the URL the profile checks with, so one round serves every group.
func injectTestURL(raw *config.RawConfig) {
	url := profileTestURL(raw)
	if url == "" {
		url = currentTestURL()
	}
	for _, group := range raw.ProxyGroup {
		if text, _ := group["url"].(string); text == "" {
			group["url"] = url
		}
	}
	for _, provider := range raw.ProxyProvider {
		check, _ := provider["health-check"].(map[string]any)
		if check == nil {
			continue
		}
		if text, _ := check["url"].(string); text == "" {
			check["url"] = url
		}
	}
}

func profileTestURL(raw *config.RawConfig) string {
	counts := map[string]int{}
	var order []string
	note := func(text string) {
		if text == "" {
			return
		}
		if counts[text] == 0 {
			order = append(order, text)
		}
		counts[text]++
	}
	for _, group := range raw.ProxyGroup {
		text, _ := group["url"].(string)
		note(text)
	}
	for _, provider := range raw.ProxyProvider {
		if check, _ := provider["health-check"].(map[string]any); check != nil {
			text, _ := check["url"].(string)
			note(text)
		}
	}
	best := ""
	for _, text := range order {
		if counts[text] > counts[best] {
			best = text
		}
	}
	return best
}

// A dialer-proxy that leads, through other dialer-proxies and the members
// of groups, back to where it started would hang every dial through it.
func dialerLoopsOf(raw *config.RawConfig) []string {
	edges := map[string][]string{}
	for _, item := range raw.Proxy {
		name, _ := item["name"].(string)
		if dialer, _ := item["dialer-proxy"].(string); name != "" && dialer != "" {
			edges[name] = append(edges[name], dialer)
		}
	}
	for _, item := range raw.ProxyGroup {
		name, _ := item["name"].(string)
		if name == "" {
			continue
		}
		if dialer, _ := item["dialer-proxy"].(string); dialer != "" {
			edges[name] = append(edges[name], dialer)
		}
		if members, _ := item["proxies"].([]any); members != nil {
			for _, member := range members {
				if text, ok := member.(string); ok {
					edges[name] = append(edges[name], text)
				}
			}
		}
	}
	const (
		unseen = iota
		visiting
		done
	)
	state := map[string]int{}
	var loops []string
	var visit func(name string) bool
	visit = func(name string) bool {
		switch state[name] {
		case visiting:
			return true
		case done:
			return false
		}
		state[name] = visiting
		looped := false
		for _, next := range edges[name] {
			if visit(next) {
				looped = true
			}
		}
		state[name] = done
		return looped
	}
	for _, item := range raw.Proxy {
		name, _ := item["name"].(string)
		if _, dials := edges[name]; dials && visit(name) {
			loops = append(loops, name)
		}
	}
	return loops
}

// Every dial through a looping dialer fails; one report stands for the burst.
const dialerLoopReportInterval = 3 * time.Second

var dialerLoopReports sync.Map

func reportDialerLoop(proxyName string) {
	now := time.Now()
	if last, ok := dialerLoopReports.Load(proxyName); ok && now.Sub(last.(time.Time)) < dialerLoopReportInterval {
		return
	}
	dialerLoopReports.Store(proxyName, now)
	logError("dialer-proxy loop through %q", proxyName)
	sendMessage(DialerLoopMessage, proxyName)
}
