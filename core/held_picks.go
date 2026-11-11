package core

import (
	"encoding/json"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/constant"
)

// mihomo builds every node afresh on an apply, alive and untested, so a
// url-test or fallback group runs the first node of its list, however dead,
// until a check reports; until then the group is held on the node it ran.

type heldPick struct {
	group    constant.Proxy // the instance held; an apply replaces it
	proxy    string
	testURL  string
	revision uint64
}

var (
	heldPicks    = map[string]heldPick{} // guarded by selectMu
	heldWatching bool
	// Counts the user's picks per group, so an apply can tell one landed
	// while it ran on the groups it replaces.
	pickRevisions = map[string]uint64{}

	heldCheckInterval = time.Second
)

// mihomo gives a group's test URL and pin out only in its JSON.
func autoGroupOf(proxy constant.Proxy) (group pickableGroup, testURL, fixed string, ok bool) {
	adapterProxy, isAdapter := proxy.(*adapter.Proxy)
	if !isAdapter {
		return nil, "", "", false
	}
	switch adapterProxy.ProxyAdapter.(type) {
	case *outboundgroup.URLTest, *outboundgroup.Fallback:
	default:
		return nil, "", "", false
	}
	group = adapterProxy.ProxyAdapter.(pickableGroup)
	data, err := group.MarshalJSON()
	if err != nil {
		return nil, "", "", false
	}
	var view struct {
		TestURL string `json:"testUrl"`
		Fixed   string `json:"fixed"`
	}
	if json.Unmarshal(data, &view) != nil {
		return nil, "", "", false
	}
	return group, view.TestURL, view.Fixed, true
}

func memberNamed(group pickableGroup, name string) constant.Proxy {
	for _, member := range group.Proxies() {
		if member.Name() == name {
			return member
		}
	}
	return nil
}

func testedFor(member constant.Proxy, testURL string) bool {
	state, ok := member.ExtraDelayHistories()[testURL]
	return ok && len(state.History) > 0
}

func carriedPicks() map[string]heldPick {
	selectMu.Lock()
	defer selectMu.Unlock()
	picks := map[string]heldPick{}
	for name, proxy := range allProxies() {
		group, testURL, fixed, ok := autoGroupOf(proxy)
		if !ok {
			continue
		}
		if held, isHeld := heldPicks[name]; isHeld && held.group == proxy && fixed == held.proxy {
			held.revision = pickRevisions[name]
			picks[name] = held
			continue
		}
		if fixed != "" {
			continue
		}
		now := group.Now()
		member := memberNamed(group, now)
		if member != nil && testedFor(member, testURL) && member.AliveForTestUrl(testURL) {
			picks[name] = heldPick{proxy: now, testURL: testURL, revision: pickRevisions[name]}
		}
	}
	return picks
}

func holdPicks(proxies map[string]constant.Proxy, carried map[string]heldPick, pinned map[string]string) {
	selectMu.Lock()
	defer selectMu.Unlock()
	clear(heldPicks)
	for name, pick := range carried {
		if pinned[name] != "" || pickRevisions[name] != pick.revision {
			continue
		}
		group, testURL, fixed, ok := autoGroupOf(proxies[name])
		if !ok || fixed != "" || testURL != pick.testURL || memberNamed(group, pick.proxy) == nil {
			continue
		}
		group.ForceSet(pick.proxy)
		pick.group = proxies[name]
		heldPicks[name] = pick
	}
	if len(heldPicks) > 0 && !heldWatching {
		heldWatching = true
		safeGo("watch held picks", watchHeldPicks)
	}
}

func watchHeldPicks() {
	for {
		time.Sleep(heldCheckInterval)
		if releaseTestedPicks() == 0 {
			return
		}
	}
}

// A fallback group runs the first node it believes alive, so the nodes
// listed before the held one must have reported too.
func checkedThrough(group pickableGroup, pick heldPick) bool {
	for _, member := range group.Proxies() {
		if !testedFor(member, pick.testURL) {
			return false
		}
		if member.Name() == pick.proxy {
			return true
		}
	}
	return false
}

// A fallback group drops a pin on a dead node itself.
func releaseTestedPicks() (held int) {
	selectMu.Lock()
	defer selectMu.Unlock()
	for name, pick := range heldPicks {
		proxy := lookupProxy(name)
		group, _, fixed, ok := autoGroupOf(proxy)
		switch {
		case !ok || proxy != pick.group || fixed != pick.proxy:
			delete(heldPicks, name)
		// A fallback group never lets go of a pin on a node it no longer has.
		case memberNamed(group, pick.proxy) == nil || checkedThrough(group, pick):
			group.ForceSet("")
			delete(heldPicks, name)
		}
	}
	if len(heldPicks) == 0 {
		heldWatching = false
	}
	return len(heldPicks)
}

// selectMu is held.
func userPicked(group string) {
	delete(heldPicks, group)
	pickRevisions[group]++
}

func heldGroups() map[string]constant.Proxy {
	selectMu.Lock()
	defer selectMu.Unlock()
	groups := make(map[string]constant.Proxy, len(heldPicks))
	for name, pick := range heldPicks {
		groups[name] = pick.group
	}
	return groups
}
