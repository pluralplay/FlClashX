package header

import "net/netip"

func (b IPv4) SourceAddr() netip.Addr {
	return netip.AddrFrom4([4]byte(b[srcAddr : srcAddr+IPv4AddressSize]))
}

func (b IPv4) DestinationAddr() netip.Addr {
	return netip.AddrFrom4([4]byte(b[dstAddr : dstAddr+IPv4AddressSize]))
}

func (b IPv4) SetSourceAddr(addr netip.Addr) {
	copy(b[srcAddr:srcAddr+IPv4AddressSize], addr.AsSlice())
}

func (b IPv4) SetDestinationAddr(addr netip.Addr) {
	copy(b[dstAddr:dstAddr+IPv4AddressSize], addr.AsSlice())
}

func (b IPv6) SourceAddr() netip.Addr {
	return netip.AddrFrom16([16]byte(b[v6SrcAddr:][:IPv6AddressSize]))
}

func (b IPv6) DestinationAddr() netip.Addr {
	return netip.AddrFrom16([16]byte(b[v6DstAddr:][:IPv6AddressSize]))
}

func (b IPv6) SetSourceAddr(addr netip.Addr) {
	copy(b[v6SrcAddr:][:IPv6AddressSize], addr.AsSlice())
}

func (b IPv6) SetDestinationAddr(addr netip.Addr) {
	copy(b[v6DstAddr:][:IPv6AddressSize], addr.AsSlice())
}
