//go:build with_gvisor

package tun

import (
	"context"
	"net/netip"
	"time"

	"github.com/metacubex/gvisor/pkg/tcpip"
	"github.com/metacubex/gvisor/pkg/tcpip/adapters/gonet"
	"github.com/metacubex/gvisor/pkg/tcpip/header"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
	"github.com/metacubex/gvisor/pkg/tcpip/transport/tcp"
	"github.com/metacubex/gvisor/pkg/waiter"
	"github.com/metacubex/sing-tun/internal/gtcpip/checksum"
	"github.com/metacubex/sing/common"
	M "github.com/metacubex/sing/common/metadata"
)

type TCPForwarder struct {
	ctx                  context.Context
	stack                *stack.Stack
	handler              Handler
	inet4LoopbackAddress []tcpip.Address
	inet6LoopbackAddress []tcpip.Address
	tun                  GVisorTun
	forwarder            *tcp.Forwarder
}

func NewTCPForwarder(ctx context.Context, stack *stack.Stack, handler Handler) *TCPForwarder {
	return NewTCPForwarderWithLoopback(ctx, stack, handler, nil, nil, nil)
}

func NewTCPForwarderWithLoopback(ctx context.Context, stack *stack.Stack, handler Handler, inet4LoopbackAddress []netip.Addr, inet6LoopbackAddress []netip.Addr, tun GVisorTun) *TCPForwarder {
	forwarder := &TCPForwarder{
		ctx:                  ctx,
		stack:                stack,
		handler:              handler,
		inet4LoopbackAddress: common.Map(inet4LoopbackAddress, AddressFromAddr),
		inet6LoopbackAddress: common.Map(inet6LoopbackAddress, AddressFromAddr),
		tun:                  tun,
	}
	forwarder.forwarder = tcp.NewForwarder(stack, 0, 1024, forwarder.Forward)
	return forwarder
}

func (f *TCPForwarder) HandlePacket(id stack.TransportEndpointID, pkt *stack.PacketBuffer) bool {
	for _, inet4LoopbackAddress := range f.inet4LoopbackAddress {
		if id.LocalAddress == inet4LoopbackAddress {
			ipHdr := pkt.Network().(header.IPv4)
			ipHdr.SetDestinationAddressWithChecksumUpdate(ipHdr.SourceAddress())
			ipHdr.SetSourceAddressWithChecksumUpdate(inet4LoopbackAddress)
			tcpHdr := header.TCP(pkt.TransportHeader().Slice())
			tcpHdr.SetChecksum(0)
			tcpHdr.SetChecksum(^checksum.Combine(pkt.Data().Checksum(), tcpHdr.CalculateChecksum(
				header.PseudoHeaderChecksum(header.TCPProtocolNumber, ipHdr.SourceAddress(), ipHdr.DestinationAddress(), ipHdr.PayloadLength()),
			)))
			f.tun.WritePacket(pkt)
			return true
		}
	}
	for _, inet6LoopbackAddress := range f.inet6LoopbackAddress {
		if id.LocalAddress == inet6LoopbackAddress {
			ipHdr := pkt.Network().(header.IPv6)
			ipHdr.SetDestinationAddress(ipHdr.SourceAddress())
			ipHdr.SetSourceAddress(inet6LoopbackAddress)
			tcpHdr := header.TCP(pkt.TransportHeader().Slice())
			tcpHdr.SetChecksum(0)
			tcpHdr.SetChecksum(^checksum.Combine(pkt.Data().Checksum(), tcpHdr.CalculateChecksum(
				header.PseudoHeaderChecksum(header.TCPProtocolNumber, ipHdr.SourceAddress(), ipHdr.DestinationAddress(), ipHdr.PayloadLength()),
			)))
			f.tun.WritePacket(pkt)
			return true
		}
	}
	return f.forwarder.HandlePacket(id, pkt)
}

func (f *TCPForwarder) Forward(r *tcp.ForwarderRequest) {
	var wq waiter.Queue
	var cancel context.CancelFunc
	if parentDone := f.ctx.Done(); parentDone != nil {
		var handshakeCtx context.Context
		handshakeCtx, cancel = context.WithCancel(context.Background())
		go func() {
			select {
			case <-parentDone:
				wq.Notify(wq.Events())
			case <-handshakeCtx.Done():
			}
		}()
	}
	endpoint, err := r.CreateEndpoint(&wq)
	if cancel != nil {
		cancel()
	}
	if err != nil {
		r.Complete(true)
		return
	}
	r.Complete(false)
	endpoint.SocketOptions().SetKeepAlive(true)
	keepAliveIdle := tcpip.KeepaliveIdleOption(15 * time.Second)
	endpoint.SetSockOpt(&keepAliveIdle)
	keepAliveInterval := tcpip.KeepaliveIntervalOption(15 * time.Second)
	endpoint.SetSockOpt(&keepAliveInterval)
	tcpConn := gonet.NewTCPConn(&wq, endpoint)
	lAddr := tcpConn.RemoteAddr()
	rAddr := tcpConn.LocalAddr()
	if lAddr == nil || rAddr == nil {
		tcpConn.Close()
		return
	}
	go func() {
		var metadata M.Metadata
		metadata.Source = M.SocksaddrFromNet(lAddr)
		metadata.Destination = M.SocksaddrFromNet(rAddr)
		hErr := f.handler.NewConnection(f.ctx, tcpConn, metadata)
		if hErr != nil {
			endpoint.Abort()
		}
	}()
}
