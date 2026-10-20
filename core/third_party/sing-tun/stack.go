package tun

import (
	"context"
	"encoding/binary"
	"net"
	"net/netip"
	"time"

	"github.com/metacubex/sing/common/control"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
)

var (
	ErrDrop  = E.New("drop by rule")
	ErrReset = E.New("reset by rule")
)

type Stack interface {
	Start() error
	Close() error
}

type StackOptions struct {
	Context                context.Context
	Tun                    Tun
	TunOptions             Options
	EndpointIndependentNat bool
	UDPTimeout             time.Duration
	ICMPTimeout            time.Duration
	Handler                Handler
	Logger                 logger.Logger
	ForwarderBindInterface bool
	IncludeAllNetworks     bool
	InterfaceFinder        control.InterfaceFinder
	TCPCongestionControl   string
	EnforceBindInterface   bool
}

func NewStack(
	stack string,
	options StackOptions,
) (Stack, error) {
	switch stack {
	case "", "mips":
		return NewMipstack(options)
	case "gvisor":
		return NewGVisor(options)
	case "mixed":
		if options.IncludeAllNetworks {
			return nil, ErrIncludeAllNetworks
		}
		return NewMixed(options)
	case "system":
		if options.IncludeAllNetworks {
			return nil, ErrIncludeAllNetworks
		}
		return NewSystem(options)
	default:
		return nil, E.New("unknown stack: ", stack)
	}
}

func HasNextAddress(prefix netip.Prefix, count int) bool {
	checkAddr := prefix.Addr()
	for i := 0; i < count; i++ {
		checkAddr = checkAddr.Next()
	}
	return prefix.Contains(checkAddr)
}

func BroadcastAddr(inet4Address []netip.Prefix) netip.Addr {
	if len(inet4Address) == 0 {
		return netip.Addr{}
	}
	prefix := inet4Address[0]
	var broadcastAddr [4]byte
	binary.BigEndian.PutUint32(broadcastAddr[:], binary.BigEndian.Uint32(prefix.Masked().Addr().AsSlice())|^binary.BigEndian.Uint32(net.CIDRMask(prefix.Bits(), 32)))
	return netip.AddrFrom4(broadcastAddr)
}
