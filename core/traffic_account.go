package core

import (
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/proxydialer"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// mihomo keeps one traffic total and announces nothing when a connection
// opens. The listeners hand their connections to this tunnel instead, which
// counts each one's bytes by whether its chain ends in a DIRECT outbound and
// finds the tracker mihomo registered for it, the moment that tells the host
// about the connection, its route and, for a probe, the exit it took.
type accountingTunnel struct {
	constant.Tunnel
}

var trafficTunnel constant.Tunnel = accountingTunnel{tunnel.Tunnel}

// The TUN listener asserts provider.Tunnel without checking and the by-name
// dialer asserts proxydialer.Tunnel, so the wrapper must keep offering what
// embedding constant.Tunnel alone hides.
var (
	_ provider.Tunnel    = accountingTunnel{}
	_ proxydialer.Tunnel = accountingTunnel{}
)

func (t accountingTunnel) HandleTCPConn(conn net.Conn, metadata *constant.Metadata) {
	t.Tunnel.HandleTCPConn(&accountedConn{Conn: conn, metadata: metadata}, metadata)
}

func (t accountingTunnel) HandleUDPPacket(packet constant.UDPPacket, metadata *constant.Metadata) {
	route := udpRoutes.routeFor(metadata)
	route.add(int64(len(packet.Data())), 0)
	t.Tunnel.HandleUDPPacket(&accountedPacket{UDPPacket: packet, route: route}, metadata)
}

func (t accountingTunnel) Proxies() map[string]constant.Proxy {
	return tunnel.Proxies()
}

func (t accountingTunnel) Providers() map[string]provider.ProxyProvider {
	return tunnel.Providers()
}

func (t accountingTunnel) RuleProviders() map[string]provider.RuleProvider {
	return tunnel.RuleProviders()
}

func (t accountingTunnel) RuleUpdateCallback() *utils.Callback[provider.RuleProvider] {
	return tunnel.Tunnel.RuleUpdateCallback()
}

type routeKind uint8

const (
	routeUnknown routeKind = iota
	routeDirect
	routeProxied
)

// The tracker that knows the chain is registered once the dial succeeds;
// bytes seen before then wait in the account until it is.
const routeLookupAttempts = 64

type trafficAccount struct {
	mu        sync.Mutex
	metadata  *constant.Metadata
	udp       bool
	route     routeKind
	trackerID string
	lookups   int
	up, down  int64
	verified  time.Time
}

func (a *trafficAccount) add(up, down int64) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.route == routeUnknown && a.lookups < routeLookupAttempts {
		a.lookups++
		if tracker := findTracker(a.matches); tracker != nil {
			a.settle(tracker)
		}
	}
	switch a.route {
	case routeProxied:
		proxiedTraffic.add(up, down)
	case routeUnknown:
		a.up += up
		a.down += down
	}
}

func (a *trafficAccount) matches(info *statistic.TrackerInfo) bool {
	if a.udp {
		return info.Metadata != nil &&
			info.Metadata.NetWork == constant.UDP &&
			info.Metadata.SourceAddrPort() == a.metadata.SourceAddrPort()
	}
	return info.Metadata == a.metadata
}

func (a *trafficAccount) settle(tracker statistic.Tracker) {
	info := tracker.Info()
	a.trackerID = tracker.ID()
	a.verified = time.Now()
	if isDirectChain(info.Chain) {
		a.route = routeDirect
	} else {
		a.route = routeProxied
		proxiedTraffic.add(a.up, a.down)
	}
	a.up, a.down = 0, 0
	onTrackerFound(tracker)
}

func isDirectChain(chain constant.Chain) bool {
	name := chain.Last()
	if proxy, ok := allProxies()[name]; ok {
		return proxy.Type() == constant.Direct
	}
	return name == "DIRECT"
}

func findTracker(matches func(*statistic.TrackerInfo) bool) statistic.Tracker {
	var found statistic.Tracker
	statistic.DefaultManager.Range(func(tracker statistic.Tracker) bool {
		if matches(tracker.Info()) {
			found = tracker
			return false
		}
		return true
	})
	return found
}

func onTrackerFound(tracker statistic.Tracker) {
	notifyProbeRoute(tracker)
	if hostWantsEvents() {
		sendMessage(RequestMessage, tracker.Info())
		watchRequestTraffic(tracker)
	}
}

type accountedConn struct {
	net.Conn
	metadata *constant.Metadata
	account  trafficAccount
	once     sync.Once
}

func (c *accountedConn) init() {
	c.account.metadata = c.metadata
}

func (c *accountedConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if n > 0 {
		c.once.Do(c.init)
		c.account.add(int64(n), 0)
	}
	return n, err
}

func (c *accountedConn) Write(b []byte) (int, error) {
	n, err := c.Conn.Write(b)
	if n > 0 {
		c.once.Do(c.init)
		c.account.add(0, int64(n))
	}
	return n, err
}

type accountedPacket struct {
	constant.UDPPacket
	route *trafficAccount
}

func (p *accountedPacket) WriteBack(b []byte, addr net.Addr) (int, error) {
	n, err := p.UDPPacket.WriteBack(b, addr)
	if n > 0 {
		p.route.add(0, int64(n))
	}
	return n, err
}

// A UDP session is one tracker for many packets, told apart by the source
// they come from; a source that falls silent is forgotten, and one that
// keeps talking is checked now and then in case mihomo opened a new session
// for it.
const (
	udpRouteIdle     = 2 * time.Minute
	udpRouteRecheck  = 30 * time.Second
	udpRouteSweepGap = 256
)

var udpRoutes = udpRouteTable{routes: map[netip.AddrPort]*udpRoute{}}

type udpRoute struct {
	trafficAccount
	lastSeen time.Time
}

type udpRouteTable struct {
	mu     sync.Mutex
	routes map[netip.AddrPort]*udpRoute
	calls  int
}

func (t *udpRouteTable) routeFor(metadata *constant.Metadata) *trafficAccount {
	key := metadata.SourceAddrPort()
	now := time.Now()
	t.mu.Lock()
	defer t.mu.Unlock()
	t.calls++
	if t.calls%udpRouteSweepGap == 0 {
		for key, route := range t.routes {
			if now.Sub(route.lastSeen) > udpRouteIdle {
				delete(t.routes, key)
			}
		}
	}
	route, ok := t.routes[key]
	if !ok {
		route = &udpRoute{trafficAccount: trafficAccount{metadata: metadata, udp: true}}
		t.routes[key] = route
	}
	route.lastSeen = now
	route.recheck(now)
	return &route.trafficAccount
}

func (r *udpRoute) recheck(now time.Time) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.route == routeUnknown || now.Sub(r.verified) < udpRouteRecheck {
		return
	}
	tracker := findTracker(r.matches)
	if tracker == nil {
		r.route, r.lookups = routeUnknown, 0
		return
	}
	r.verified = now
	if tracker.ID() != r.trackerID {
		r.settle(tracker)
	}
}

type trafficTotals struct {
	up, down atomic.Int64
}

func (t *trafficTotals) add(up, down int64) {
	if up != 0 {
		t.up.Add(up)
	}
	if down != 0 {
		t.down.Add(down)
	}
}

func (t *trafficTotals) reset() {
	t.up.Store(0)
	t.down.Store(0)
}

var proxiedTraffic trafficTotals

// The host asks once a second; the speed is what moved since it last asked.
var proxiedSpeed struct {
	sync.Mutex
	up, down int64
	at       time.Time
}

func proxiedTrafficNow() (up, down int64) {
	totalUp, totalDown := proxiedTraffic.up.Load(), proxiedTraffic.down.Load()
	now := time.Now()
	proxiedSpeed.Lock()
	defer proxiedSpeed.Unlock()
	elapsed := now.Sub(proxiedSpeed.at)
	lastUp, lastDown := proxiedSpeed.up, proxiedSpeed.down
	proxiedSpeed.up, proxiedSpeed.down, proxiedSpeed.at = totalUp, totalDown, now
	if lastUp == 0 && lastDown == 0 && elapsed > time.Hour || elapsed <= 0 {
		return 0, 0
	}
	scale := float64(time.Second) / float64(elapsed)
	return int64(float64(totalUp-lastUp) * scale), int64(float64(totalDown-lastDown) * scale)
}

func resetProxiedTraffic() {
	proxiedTraffic.reset()
	proxiedSpeed.Lock()
	proxiedSpeed.up, proxiedSpeed.down, proxiedSpeed.at = 0, 0, time.Now()
	proxiedSpeed.Unlock()
}
