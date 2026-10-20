//go:build with_gvisor

package ping

import (
	"context"
	"net/netip"
	"time"

	"github.com/metacubex/gvisor/pkg/tcpip"
	"github.com/metacubex/gvisor/pkg/tcpip/adapters/gonet"
	"github.com/metacubex/gvisor/pkg/tcpip/header"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
	"github.com/metacubex/gvisor/pkg/tcpip/transport"
	"github.com/metacubex/gvisor/pkg/waiter"
	"github.com/metacubex/sing-tun"
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/buf"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
)

var _ tun.DirectRouteDestination = (*GVisorDestination)(nil)

type GVisorDestination struct {
	ctx        context.Context
	logger     logger.ContextLogger
	endpoint   tcpip.Endpoint
	conn       *gonet.TCPConn
	rewriter   *SourceRewriter
	timeout    time.Duration
	lastActive common.TypedValue[time.Time]
}

func ConnectGVisor(
	ctx context.Context, logger logger.ContextLogger,
	sourceAddress, destinationAddress netip.Addr,
	routeContext tun.DirectRouteContext,
	stack *stack.Stack,
	bindAddress4, bindAddress6 netip.Addr,
	timeout time.Duration,
) (*GVisorDestination, error) {
	var (
		bindAddress tcpip.Address
		wq          waiter.Queue
		endpoint    tcpip.Endpoint
		gErr        tcpip.Error
	)
	if !destinationAddress.Is6() {
		if !bindAddress4.IsValid() {
			return nil, E.New("missing IPv4 interface address")
		}
		bindAddress = tun.AddressFromAddr(bindAddress4)
		endpoint, gErr = stack.NewRawEndpoint(header.ICMPv4ProtocolNumber, header.IPv4ProtocolNumber, &wq, true)
	} else {
		if !bindAddress6.IsValid() {
			return nil, E.New("missing IPv6 interface address")
		}
		bindAddress = tun.AddressFromAddr(bindAddress6)
		endpoint, gErr = stack.NewRawEndpoint(header.ICMPv6ProtocolNumber, header.IPv6ProtocolNumber, &wq, true)
	}
	if gErr != nil {
		return nil, gonet.TranslateNetstackError(gErr)
	}
	gErr = endpoint.Bind(tcpip.FullAddress{
		NIC:  1,
		Addr: bindAddress,
	})
	if gErr != nil {
		return nil, gonet.TranslateNetstackError(gErr)
	}
	gErr = endpoint.Connect(tcpip.FullAddress{
		NIC:  1,
		Addr: tun.AddressFromAddr(destinationAddress),
	})
	if gErr != nil {
		return nil, gonet.TranslateNetstackError(gErr)
	}
	endpoint.SocketOptions().SetHeaderIncluded(true)
	rewriter := NewSourceRewriter(ctx, logger, bindAddress4, bindAddress6)
	rewriter.CreateSession(tun.DirectRouteSession{Source: sourceAddress, Destination: destinationAddress}, routeContext)
	destination := &GVisorDestination{
		ctx:      ctx,
		logger:   logger,
		endpoint: endpoint,
		conn:     gonet.NewTCPConn(&wq, endpoint),
		rewriter: rewriter,
		timeout:  timeout,
	}
	destination.lastActive.Store(time.Now())
	go destination.loopRead()
	return destination, nil
}

func (d *GVisorDestination) loopRead() {
	defer d.endpoint.Close()
	for {
		deadline := d.lastActive.Load().Add(d.timeout)
		if !time.Now().Before(deadline) {
			return
		}
		err := d.conn.SetReadDeadline(deadline)
		if err != nil {
			d.logger.ErrorContext(d.ctx, E.Cause(err, "set read deadline for ICMP conn"))
		}
		buffer := buf.NewSize(maxICMPPacketSize)
		n, err := d.conn.Read(buffer.FreeBytes())
		if err != nil {
			buffer.Release()
			if E.IsTimeout(err) {
				continue
			}
			if !E.IsClosed(err) {
				d.logger.ErrorContext(d.ctx, E.Cause(err, "receive ICMP echo reply"))
			}
			return
		}
		buffer.Truncate(n)
		var matched bool
		matched, err = d.rewriter.WriteBack(buffer.Bytes())
		if err != nil {
			d.logger.ErrorContext(d.ctx, E.Cause(err, "write ICMP echo reply"))
		}
		if matched {
			d.lastActive.Store(time.Now())
		}
		buffer.Release()
	}
}

func (d *GVisorDestination) WritePacket(packet *buf.Buffer) error {
	d.lastActive.Store(time.Now())
	d.rewriter.RewritePacket(packet.Bytes())
	return common.Error(d.conn.Write(packet.Bytes()))
}

func (d *GVisorDestination) Close() error {
	return d.conn.Close()
}

func (d *GVisorDestination) IsClosed() bool {
	return transport.DatagramEndpointState(d.endpoint.State()) == transport.DatagramEndpointStateClosed
}
