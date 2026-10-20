package tun

import (
	"os"

	mips "github.com/metacubex/mipstack"
	"github.com/metacubex/sing/common/buf"
	E "github.com/metacubex/sing/common/exceptions"
	M "github.com/metacubex/sing/common/metadata"
	N "github.com/metacubex/sing/common/network"
)

func (s *Mipstack) forwardUDP(request *mips.UDPForwarderRequest) {
	flow := request.Flow()
	buffer := buf.NewSize(len(request.Payload()))
	_, _ = buffer.Write(request.Payload())
	responder, err := request.DetachForReplies()
	if err != nil {
		buffer.Release()
		return
	}
	s.handler.NewPacket(
		s.ctx,
		flow.Source,
		buffer,
		M.Metadata{
			Source:      M.SocksaddrFromNetIP(flow.Source),
			Destination: M.SocksaddrFromNetIP(flow.Destination),
		},
		func(N.PacketConn) N.PacketWriter {
			return &mipsUDPWriter{responder: responder}
		},
	)
}

type mipsUDPWriter struct {
	responder *mips.UDPForwarderResponder
}

func (w *mipsUDPWriter) WritePacket(buffer *buf.Buffer, destination M.Socksaddr) error {
	defer buffer.Release()
	if !destination.IsIP() {
		return E.Cause(os.ErrInvalid, "invalid destination")
	}
	_, err := w.responder.ReplyFrom(buffer.Bytes(), destination.AddrPort())
	return err
}
