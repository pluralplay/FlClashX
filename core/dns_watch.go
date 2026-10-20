package core

import (
	"context"
	"net/netip"
	"time"

	"github.com/metacubex/mihomo/component/resolver"
	D "github.com/miekg/dns"
)

const (
	initiatorRule   = "rule"
	initiatorProxy  = "proxy"
	initiatorDirect = "direct"
	initiatorApp    = "app"
)

type dnsQueryRecord struct {
	Question  D.Question
	Msg       *D.Msg
	Err       error
	Initiator string
	Upstream  string
	Cached    bool
	Start     time.Time
}

// mihomo resolves through three package-level resolvers, one per kind of
// caller; each is wrapped after an apply (which installs fresh ones) so the
// host's DNS page sees the queries and who asked. The wrapper does nothing
// while nobody listens.
type watchedResolver struct {
	resolver.Resolver
	initiator string
}

func watchResolvers() {
	resolver.DefaultResolver = watchResolver(resolver.DefaultResolver, initiatorRule)
	resolver.ProxyServerHostResolver = watchResolver(resolver.ProxyServerHostResolver, initiatorProxy)
	resolver.DirectHostResolver = watchResolver(resolver.DirectHostResolver, initiatorDirect)
}

func watchResolver(r resolver.Resolver, initiator string) resolver.Resolver {
	if r == nil {
		return nil
	}
	if watched, ok := r.(*watchedResolver); ok {
		return watched
	}
	return &watchedResolver{Resolver: r, initiator: initiator}
}

func (r *watchedResolver) LookupIP(ctx context.Context, host string) ([]netip.Addr, error) {
	start := time.Now()
	ips, err := r.Resolver.LookupIP(ctx, host)
	r.reportLookup(host, ips, err, start)
	return ips, err
}

func (r *watchedResolver) LookupIPv4(ctx context.Context, host string) ([]netip.Addr, error) {
	start := time.Now()
	ips, err := r.Resolver.LookupIPv4(ctx, host)
	r.reportLookup(host, ips, err, start)
	return ips, err
}

func (r *watchedResolver) LookupIPv6(ctx context.Context, host string) ([]netip.Addr, error) {
	start := time.Now()
	ips, err := r.Resolver.LookupIPv6(ctx, host)
	r.reportLookup(host, ips, err, start)
	return ips, err
}

func (r *watchedResolver) ExchangeContext(ctx context.Context, m *D.Msg) (*D.Msg, error) {
	start := time.Now()
	msg, err := r.Resolver.ExchangeContext(ctx, m)
	if hostWantsEvents() && len(m.Question) > 0 {
		sendMessage(DnsMessage, newDnsQuery(dnsQueryRecord{
			Question:  m.Question[0],
			Msg:       msg,
			Err:       err,
			Initiator: r.initiator,
			Start:     start,
		}))
	}
	return msg, err
}

func (r *watchedResolver) reportLookup(host string, ips []netip.Addr, err error, start time.Time) {
	if !hostWantsEvents() {
		return
	}
	name := D.Fqdn(host)
	qtype := uint16(D.TypeA)
	if len(ips) > 0 && ips[0].Unmap().Is6() {
		qtype = D.TypeAAAA
	}
	msg := &D.Msg{}
	for _, ip := range ips {
		header := D.RR_Header{Name: name, Class: D.ClassINET}
		if ip.Unmap().Is4() {
			header.Rrtype = D.TypeA
			msg.Answer = append(msg.Answer, &D.A{Hdr: header, A: ip.Unmap().AsSlice()})
		} else {
			header.Rrtype = D.TypeAAAA
			msg.Answer = append(msg.Answer, &D.AAAA{Hdr: header, AAAA: ip.AsSlice()})
		}
	}
	if err != nil {
		msg = nil
	}
	sendMessage(DnsMessage, newDnsQuery(dnsQueryRecord{
		Question:  D.Question{Name: name, Qtype: qtype, Qclass: D.ClassINET},
		Msg:       msg,
		Err:       err,
		Initiator: r.initiator,
		Start:     start,
	}))
}
