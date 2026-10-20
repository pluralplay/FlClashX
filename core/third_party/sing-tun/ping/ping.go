package ping

import (
	"context"
	"net"
	"net/netip"
	"reflect"
	"runtime"
	"sync/atomic"
	"time"

	"github.com/metacubex/sing-tun/internal/gtcpip/header"
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/buf"
	"github.com/metacubex/sing/common/control"
	E "github.com/metacubex/sing/common/exceptions"
	M "github.com/metacubex/sing/common/metadata"

	"golang.org/x/net/ipv4"
	"golang.org/x/net/ipv6"
)

type Conn struct {
	ctx         context.Context
	privileged  bool
	conn        net.Conn
	destination netip.Addr
	source      common.TypedValue[netip.Addr]
	closed      atomic.Bool
	readMsg     func(b, oob []byte) (n, oobn int, addr netip.Addr, err error)
}

func Connect(ctx context.Context, privileged bool, controlFunc control.Func, destination netip.Addr, idleTimeout time.Duration) (*Conn, error) {
	c := &Conn{
		ctx:         ctx,
		privileged:  privileged,
		destination: destination,
	}
	err := c.connect(controlFunc, idleTimeout)
	if err != nil {
		return nil, err
	}
	return c, nil
}

func (c *Conn) connect(controlFunc control.Func, idleTimeout time.Duration) (err error) {
	if c.isLinuxUnprivileged() {
		c.conn, err = newUnprivilegedConn(c.ctx, controlFunc, c.destination, idleTimeout)
	} else {
		c.conn, err = connect(c.privileged, controlFunc, c.destination)
	}
	if err != nil {
		return err
	}
	if ipConn, isIPConn := common.Cast[*net.IPConn](c.conn); isIPConn {
		c.readMsg = func(b, oob []byte) (n, oobn int, addr netip.Addr, err error) {
			var ipAddr *net.IPAddr
			n, oobn, _, ipAddr, err = ipConn.ReadMsgIP(b, oob)
			if err == nil {
				addr = M.AddrFromNet(ipAddr)
			}
			return
		}
	} else if udpConn, isUDPConn := common.Cast[*net.UDPConn](c.conn); isUDPConn {
		c.readMsg = func(b, oob []byte) (n, oobn int, addr netip.Addr, err error) {
			var addrPort netip.AddrPort
			n, oobn, _, addrPort, err = udpConn.ReadMsgUDPAddrPort(b, oob)
			if err == nil {
				addr = addrPort.Addr()
			}
			return
		}
	} else if unprivilegedConn, isUnprivilegedConn := c.conn.(*UnprivilegedConn); isUnprivilegedConn {
		c.readMsg = unprivilegedConn.ReadMsg
	} else {
		return E.New("unsupported conn type: ", reflect.TypeOf(c.conn))
	}
	return
}

func (c *Conn) isLinuxUnprivileged() bool {
	return (runtime.GOOS == "linux" || runtime.GOOS == "android") && !c.privileged
}

func (c *Conn) ReadIP(buffer *buf.Buffer) error {
	if c.destination.Is6() || c.isLinuxUnprivileged() {
		if !c.destination.Is6() {
			oob := ipv4.NewControlMessage(ipv4.FlagTTL)
			buffer.Advance(header.IPv4MinimumSize)
			var ttl int
			// tos int
			n, oobn, addr, err := c.readMsg(buffer.FreeBytes(), oob)
			if err != nil {
				return err
			}
			buffer.Truncate(n)
			if oobn > 0 {
				var controlMessage ipv4.ControlMessage
				err = controlMessage.Parse(oob[:oobn])
				if err != nil {
					return err
				}
				ttl = controlMessage.TTL
			}
			if !c.isLinuxUnprivileged() {
				icmpHdr := header.ICMPv4(buffer.Bytes())
				icmpHdr.SetIdent(^icmpHdr.Ident())
				icmpHdr.SetChecksum(header.ICMPv4Checksum(icmpHdr, 0))
			}
			ipHdr := header.IPv4(buffer.ExtendHeader(header.IPv4MinimumSize))
			ipHdr.Encode(&header.IPv4Fields{
				// TOS:         uint8(tos),
				SrcAddr:     addr,
				DstAddr:     c.source.Load(),
				Protocol:    uint8(header.ICMPv4ProtocolNumber),
				TTL:         uint8(ttl),
				TotalLength: uint16(buffer.Len()),
			})
			ipHdr.SetChecksum(^ipHdr.CalculateChecksum())
		} else {
			oob := make([]byte, 1024)
			buffer.Advance(header.IPv6MinimumSize)
			var (
				hopLimit     int
				trafficClass int
			)
			n, oobn, addr, err := c.readMsg(buffer.FreeBytes(), oob)
			if err != nil {
				return err
			}
			buffer.Truncate(n)
			if oobn > 0 {
				var controlMessage *ipv6.ControlMessage
				controlMessage, err = parseIPv6ControlMessage(oob[:oobn])
				if err != nil {
					return err
				}
				hopLimit = controlMessage.HopLimit
				trafficClass = controlMessage.TrafficClass
			}
			icmpHdr := header.ICMPv6(buffer.Bytes())
			if !c.isLinuxUnprivileged() {
				icmpHdr.SetIdent(^icmpHdr.Ident())
			}
			icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
				Header: icmpHdr,
				Src:    addr.AsSlice(),
				Dst:    c.source.Load().AsSlice(),
			}))
			ipHdr := header.IPv6(buffer.ExtendHeader(header.IPv6MinimumSize))
			ipHdr.Encode(&header.IPv6Fields{
				TrafficClass:      uint8(trafficClass),
				PayloadLength:     uint16(buffer.Len() - header.IPv6MinimumSize),
				TransportProtocol: header.ICMPv6ProtocolNumber,
				HopLimit:          uint8(hopLimit),
				SrcAddr:           addr,
				DstAddr:           c.source.Load(),
			})
		}
	} else {
		_, err := buffer.ReadOnceFrom(c.conn)
		if err != nil {
			return err
		}
		if !c.destination.Is6() {
			ipHdr := header.IPv4(buffer.Bytes())
			if runtime.GOOS == "darwin" || runtime.GOOS == "ios" {
				// MacOS have different TotalLen and FragOff in ipv4 header from socket api:
				// https://stackoverflow.com/questions/13829712/mac-changes-ip-total-length-field/15881825#15881825
				// but in the tun api still same data format as other system
				ipHdr.SetTotalLength(ipHdr.TotalLengthDarwinRaw())
				ipHdr.SetFlagsFragmentOffset(ipHdr.FlagsDarwinRaw(), ipHdr.FragmentOffsetDarwinRaw())
			}
			if !ipHdr.IsValid(buffer.Len()) {
				return E.New("invalid IPv4 header received")
			}
			ipHdr.SetDestinationAddr(c.source.Load())
			ipHdr.SetChecksum(^ipHdr.CalculateChecksum())
			icmpHdr := header.ICMPv4(ipHdr.Payload())
			if !c.isLinuxUnprivileged() {
				icmpHdr.SetIdent(^icmpHdr.Ident())
			}
			icmpHdr.SetChecksum(header.ICMPv4Checksum(icmpHdr, 0))
		} else {
			ipHdr := header.IPv6(buffer.Bytes())
			if !ipHdr.IsValid(buffer.Len()) {
				return E.New("invalid IPv6 header received")
			}
			ipHdr.SetDestinationAddr(c.source.Load())
			icmpHdr := header.ICMPv6(ipHdr.Payload())
			if !c.isLinuxUnprivileged() {
				icmpHdr.SetIdent(^icmpHdr.Ident())
			}
			icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
				Header: icmpHdr,
				Src:    ipHdr.SourceAddressSlice(),
				Dst:    ipHdr.DestinationAddressSlice(),
			}))
		}
	}
	return nil
}

func (c *Conn) ReadICMP(buffer *buf.Buffer) error {
	_, err := buffer.ReadOnceFrom(c.conn)
	if err != nil {
		return err
	}
	if !c.isLinuxUnprivileged() {
		if !c.destination.Is6() {
			ipHdr := header.IPv4(buffer.Bytes())
			buffer.Advance(int(ipHdr.HeaderLength()))

			icmpHdr := header.ICMPv4(buffer.Bytes())
			icmpHdr.SetIdent(^icmpHdr.Ident())
			icmpHdr.SetChecksum(header.ICMPv4Checksum(icmpHdr, 0))
		} else {
			icmpHdr := header.ICMPv6(buffer.Bytes())
			icmpHdr.SetIdent(^icmpHdr.Ident())
			icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
				Header: icmpHdr,
				Src:    c.destination.AsSlice(),
				Dst:    c.source.Load().AsSlice(),
			}))
		}
	}
	return nil
}

func (c *Conn) WriteIP(buffer *buf.Buffer) error {
	defer buffer.Release()
	if !c.destination.Is6() {
		ipHdr := header.IPv4(buffer.Bytes())
		if !c.isLinuxUnprivileged() {
			icmpHdr := header.ICMPv4(ipHdr.Payload())
			icmpHdr.SetIdent(^icmpHdr.Ident())
			icmpHdr.SetChecksum(header.ICMPv4Checksum(icmpHdr, 0))
		}
		c.source.Store(M.AddrFromIP(ipHdr.SourceAddressSlice()))
		return common.Error(c.conn.Write(ipHdr.Payload()))
	} else {
		ipHdr := header.IPv6(buffer.Bytes())
		if !c.isLinuxUnprivileged() {
			icmpHdr := header.ICMPv6(ipHdr.Payload())
			icmpHdr.SetIdent(^icmpHdr.Ident())
			icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
				Header: icmpHdr,
				Src:    ipHdr.SourceAddressSlice(),
				Dst:    ipHdr.DestinationAddressSlice(),
			}))
		}
		c.source.Store(M.AddrFromIP(ipHdr.SourceAddressSlice()))
		return common.Error(c.conn.Write(ipHdr.Payload()))
	}
}

func (c *Conn) WriteICMP(buffer *buf.Buffer) error {
	defer buffer.Release()
	if !c.isLinuxUnprivileged() {
		if !c.destination.Is6() {
			icmpHdr := header.ICMPv4(buffer.Bytes())
			icmpHdr.SetIdent(^icmpHdr.Ident())
			icmpHdr.SetChecksum(header.ICMPv4Checksum(icmpHdr, 0))
		} else {
			icmpHdr := header.ICMPv6(buffer.Bytes())
			icmpHdr.SetIdent(^icmpHdr.Ident())
			icmpHdr.SetChecksum(header.ICMPv6Checksum(header.ICMPv6ChecksumParams{
				Header: icmpHdr,
				Src:    c.source.Load().AsSlice(),
				Dst:    c.destination.AsSlice(),
			}))
		}
	}
	return common.Error(c.conn.Write(buffer.Bytes()))
}

func (c *Conn) SetLocalAddr(addr netip.Addr) {
	c.source.Store(addr)
}

func (c *Conn) SetReadDeadline(t time.Time) error {
	return c.conn.SetReadDeadline(t)
}

func (c *Conn) Close() error {
	defer c.closed.Store(true)
	return c.conn.Close()
}

func (c *Conn) IsClosed() bool {
	return c.closed.Load()
}
