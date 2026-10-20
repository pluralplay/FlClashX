package ping

import (
	"net/netip"

	"github.com/metacubex/sing-tun"
	"github.com/metacubex/sing-tun/internal/gtcpip/header"
	"github.com/metacubex/sing/common/buf"
)

type DestinationWriter struct {
	tun.DirectRouteDestination
	destination netip.Addr
}

func NewDestinationWriter(routeDestination tun.DirectRouteDestination, destination netip.Addr) *DestinationWriter {
	return &DestinationWriter{routeDestination, destination}
}

func (w *DestinationWriter) WritePacket(packet *buf.Buffer) error {
	var ipHdr header.Network
	switch header.IPVersion(packet.Bytes()) {
	case header.IPv4Version:
		ipHdr = header.IPv4(packet.Bytes())
	case header.IPv6Version:
		ipHdr = header.IPv6(packet.Bytes())
	default:
		return w.DirectRouteDestination.WritePacket(packet)
	}
	ipHdr.SetDestinationAddr(w.destination)
	if ipHdr4, isIPv4 := ipHdr.(header.IPv4); isIPv4 {
		ipHdr4.SetChecksum(^ipHdr4.CalculateChecksum())
	}
	if ipHdr.TransportProtocol() == header.ICMPv6ProtocolNumber {
		icmpHdr := header.ICMPv6(ipHdr.Payload())
		icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
			Header: icmpHdr,
			Src:    ipHdr.SourceAddressSlice(),
			Dst:    ipHdr.DestinationAddressSlice(),
		}))
	}
	return w.DirectRouteDestination.WritePacket(packet)
}

type ContextDestinationWriter struct {
	tun.DirectRouteContext
	destination netip.Addr
}

func NewContextDestinationWriter(context tun.DirectRouteContext, destination netip.Addr) *ContextDestinationWriter {
	return &ContextDestinationWriter{
		context, destination,
	}
}

func (w *ContextDestinationWriter) WritePacket(packet []byte) error {
	var ipHdr header.Network
	switch header.IPVersion(packet) {
	case header.IPv4Version:
		ipHdr = header.IPv4(packet)
	case header.IPv6Version:
		ipHdr = header.IPv6(packet)
	default:
		return w.DirectRouteContext.WritePacket(packet)
	}
	ipHdr.SetSourceAddr(w.destination)
	if ipHdr4, isIPv4 := ipHdr.(header.IPv4); isIPv4 {
		ipHdr4.SetChecksum(^ipHdr4.CalculateChecksum())
	}
	if ipHdr.TransportProtocol() == header.ICMPv6ProtocolNumber {
		icmpHdr := header.ICMPv6(ipHdr.Payload())
		icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
			Header: icmpHdr,
			Src:    ipHdr.SourceAddressSlice(),
			Dst:    ipHdr.DestinationAddressSlice(),
		}))
	}
	return w.DirectRouteContext.WritePacket(packet)
}
