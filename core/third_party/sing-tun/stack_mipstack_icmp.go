package tun

import (
	"errors"
	"time"

	mips "github.com/metacubex/mipstack"
	"github.com/metacubex/sing/common/buf"
	M "github.com/metacubex/sing/common/metadata"
	N "github.com/metacubex/sing/common/network"
)

func (s *Mipstack) forwardICMP(request *mips.ICMPForwarderRequest) {
	message := request.Message()
	if !message.IsEchoRequest() {
		_ = request.Drop()
		return
	}
	if message.Destination == s.inet4Address || message.Destination == s.inet6Address {
		_ = request.ReplyEcho()
		_ = request.Drop()
		return
	}
	select {
	case s.icmpSlots <- struct{}{}:
	default:
		_ = request.Drop()
		return
	}
	responder, err := request.Detach()
	if err != nil {
		<-s.icmpSlots
		return
	}
	go func() {
		defer func() { <-s.icmpSlots }()
		s.forwardDetachedICMP(responder)
	}()
}

func (s *Mipstack) forwardDetachedICMP(responder *mips.ICMPForwarderResponder) {
	message := responder.Message()
	writer := &mipsICMPWriter{responder: responder}
	action, err := s.icmpMapping.Lookup(DirectRouteSession{Source: message.Source, Destination: message.Destination}, func(timeout time.Duration) (DirectRouteDestination, error) {
		destination, err := s.handler.PrepareConnection(
			N.NetworkICMP,
			M.SocksaddrFrom(message.Source, 0),
			M.SocksaddrFrom(message.Destination, 0),
			writer,
			timeout,
		)
		if err != nil {
			if destination != nil {
				_ = destination.Close()
			}
			return nil, err
		}
		return destination, nil
	})
	if errors.Is(err, ErrReset) {
		_ = responder.Reject()
		return
	} else if errors.Is(err, ErrDrop) {
		_ = responder.Drop()
		return
	}
	if action != nil {
		packet := responder.IPPacket()
		buffer := buf.NewSize(len(packet))
		_, _ = buffer.Write(packet)
		_ = action.WritePacket(buffer)
		return
	}
	_ = responder.ReplyEcho()
	_ = responder.Drop()
}

type mipsICMPWriter struct {
	responder *mips.ICMPForwarderResponder
}

func (w *mipsICMPWriter) WritePacket(packet []byte) error {
	return w.responder.ReplyIPPacket(packet)
}
