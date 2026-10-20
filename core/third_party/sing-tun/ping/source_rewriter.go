package ping

import (
	"context"
	"net/netip"
	"sync"

	"github.com/metacubex/sing-tun"
	"github.com/metacubex/sing-tun/internal/gtcpip/header"
	"github.com/metacubex/sing/common/logger"
)

type SourceRewriter struct {
	ctx           context.Context
	logger        logger.ContextLogger
	access        sync.RWMutex
	sessions      map[tun.DirectRouteSession]tun.DirectRouteContext
	sourceAddress map[uint16]netip.Addr
	inet4Address  netip.Addr
	inet6Address  netip.Addr
}

func NewSourceRewriter(ctx context.Context, logger logger.ContextLogger, inet4Address netip.Addr, inet6Address netip.Addr) *SourceRewriter {
	return &SourceRewriter{
		ctx:           ctx,
		logger:        logger,
		sessions:      make(map[tun.DirectRouteSession]tun.DirectRouteContext),
		sourceAddress: make(map[uint16]netip.Addr),
		inet4Address:  inet4Address,
		inet6Address:  inet6Address,
	}
}

func (m *SourceRewriter) CreateSession(session tun.DirectRouteSession, context tun.DirectRouteContext) {
	m.access.Lock()
	m.sessions[session] = context
	m.access.Unlock()
}

func (m *SourceRewriter) DeleteSession(session tun.DirectRouteSession) {
	m.access.Lock()
	delete(m.sessions, session)
	m.access.Unlock()
}

func (m *SourceRewriter) RewritePacket(packet []byte) {
	var ipHdr header.Network
	var bindAddr netip.Addr
	switch header.IPVersion(packet) {
	case header.IPv4Version:
		ipHdr = header.IPv4(packet)
		bindAddr = m.inet4Address
	case header.IPv6Version:
		ipHdr = header.IPv6(packet)
		bindAddr = m.inet6Address
	default:
		return
	}
	sourceAddr := ipHdr.SourceAddr()
	ipHdr.SetSourceAddr(bindAddr)
	if ipHdr4, isIPv4 := ipHdr.(header.IPv4); isIPv4 {
		ipHdr4.SetChecksum(^ipHdr4.CalculateChecksum())
	}
	switch ipHdr.TransportProtocol() {
	case header.ICMPv4ProtocolNumber:
		icmpHdr := header.ICMPv4(ipHdr.Payload())
		m.access.Lock()
		m.sourceAddress[icmpHdr.Ident()] = sourceAddr
		m.access.Unlock()
		m.logger.TraceContext(m.ctx, "write ICMPv4 echo request from ", ipHdr.SourceAddr(), " to ", ipHdr.DestinationAddr(), " id ", icmpHdr.Ident(), " seq ", icmpHdr.Sequence())
	case header.ICMPv6ProtocolNumber:
		icmpHdr := header.ICMPv6(ipHdr.Payload())
		icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
			Header: icmpHdr,
			Src:    ipHdr.SourceAddressSlice(),
			Dst:    ipHdr.DestinationAddressSlice(),
		}))
		m.access.Lock()
		m.sourceAddress[icmpHdr.Ident()] = sourceAddr
		m.access.Unlock()
		m.logger.TraceContext(m.ctx, "write ICMPv6 echo request from ", ipHdr.SourceAddr(), " to ", ipHdr.DestinationAddr(), " id ", icmpHdr.Ident(), " seq ", icmpHdr.Sequence())
	}
}

func (m *SourceRewriter) WriteBack(packet []byte) (bool, error) {
	var ipHdr header.Network
	var routeSession tun.DirectRouteSession
	switch header.IPVersion(packet) {
	case header.IPv4Version:
		ipHdr = header.IPv4(packet)
		routeSession.Destination = ipHdr.SourceAddr()
	case header.IPv6Version:
		ipHdr = header.IPv6(packet)
		routeSession.Destination = ipHdr.SourceAddr()
	default:
		return false, nil
	}
	switch ipHdr.TransportProtocol() {
	case header.ICMPv4ProtocolNumber:
		icmpHdr := header.ICMPv4(ipHdr.Payload())
		m.access.Lock()
		ident := icmpHdr.Ident()
		source, loaded := m.sourceAddress[ident]
		if !loaded {
			m.access.Unlock()
			return false, nil
		}
		delete(m.sourceAddress, icmpHdr.Ident())
		m.access.Unlock()
		routeSession.Source = source
	case header.ICMPv6ProtocolNumber:
		icmpHdr := header.ICMPv6(ipHdr.Payload())
		m.access.Lock()
		ident := icmpHdr.Ident()
		source, loaded := m.sourceAddress[ident]
		if !loaded {
			m.access.Unlock()
			return false, nil
		}
		delete(m.sourceAddress, icmpHdr.Ident())
		m.access.Unlock()
		routeSession.Source = source
	default:
		return false, nil
	}
	m.access.RLock()
	context, loaded := m.sessions[routeSession]
	m.access.RUnlock()
	if !loaded {
		return false, nil
	}
	ipHdr.SetDestinationAddr(routeSession.Source)
	if ipHdr4, isIPv4 := ipHdr.(header.IPv4); isIPv4 {
		ipHdr4.SetChecksum(^ipHdr4.CalculateChecksum())
	}
	switch ipHdr.TransportProtocol() {
	case header.ICMPv4ProtocolNumber:
		icmpHdr := header.ICMPv4(ipHdr.Payload())
		m.logger.TraceContext(m.ctx, "read ICMPv4 echo reply from ", ipHdr.SourceAddr(), " to ", ipHdr.DestinationAddr(), " id ", icmpHdr.Ident(), " seq ", icmpHdr.Sequence())
	case header.ICMPv6ProtocolNumber:
		icmpHdr := header.ICMPv6(ipHdr.Payload())
		icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
			Header: icmpHdr,
			Src:    ipHdr.SourceAddressSlice(),
			Dst:    ipHdr.DestinationAddressSlice(),
		}))
		m.logger.TraceContext(m.ctx, "read ICMPv6 echo reply from ", ipHdr.SourceAddr(), " to ", ipHdr.DestinationAddr(), " id ", icmpHdr.Ident(), " seq ", icmpHdr.Sequence())
	}
	return true, context.WritePacket(packet)
}
