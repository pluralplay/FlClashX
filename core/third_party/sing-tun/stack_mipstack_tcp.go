package tun

import (
	mips "github.com/metacubex/mipstack"
	M "github.com/metacubex/sing/common/metadata"
)

func (s *Mipstack) forwardTCP(request *mips.TCPForwarderRequest) {
	flow := request.Flow()
	conn, err := request.Accept(s.ctx)
	if err != nil {
		return
	}
	metadata := M.Metadata{
		Source:      M.SocksaddrFromNetIP(flow.Source),
		Destination: M.SocksaddrFromNetIP(flow.Destination),
	}
	go func() {
		if err := s.handler.NewConnection(s.ctx, conn, metadata); err != nil {
			_ = conn.SetLinger(0)
			_ = conn.Close()
		}
	}()
}
