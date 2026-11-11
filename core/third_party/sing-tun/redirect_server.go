//go:build linux

package tun

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"sync/atomic"
	"time"

	"github.com/metacubex/sing/common/control"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
	M "github.com/metacubex/sing/common/metadata"
)

const ProtocolRedirect = "redirect"

type redirectServer struct {
	ctx        context.Context
	handler    Handler
	logger     logger.Logger
	listenAddr netip.Addr
	listener   *net.TCPListener
	inShutdown atomic.Bool
}

func newRedirectServer(ctx context.Context, handler Handler, logger logger.Logger, listenAddr netip.Addr) *redirectServer {
	return &redirectServer{
		ctx:        ctx,
		handler:    handler,
		logger:     logger,
		listenAddr: listenAddr,
	}
}

func (s *redirectServer) Start() error {
	var listenConfig net.ListenConfig
	// listenConfig.KeepAlive = C.TCPKeepAliveInitial
	listenConfig.KeepAlive = 10 * time.Minute
	listener, err := listenConfig.Listen(s.ctx, M.NetworkFromNetAddr("tcp", s.listenAddr), M.SocksaddrFrom(s.listenAddr, 0).String())
	if err != nil {
		return err
	}
	s.listener = listener.(*net.TCPListener)
	go s.loopIn()
	return nil
}

func (s *redirectServer) Close() error {
	s.inShutdown.Store(true)
	return s.listener.Close()
}

func (s *redirectServer) loopIn() {
	for {
		conn, err := s.listener.AcceptTCP()
		if err != nil {
			var netError net.Error
			//goland:noinspection GoDeprecation
			//nolint:staticcheck
			if errors.As(err, &netError) && netError.Temporary() {
				s.logger.Error(err)
				continue
			}
			if s.inShutdown.Load() && E.IsClosed(err) {
				return
			}
			s.listener.Close()
			s.logger.Error("serve error: ", err)
			continue
		}
		var metadata M.Metadata
		metadata.Protocol = ProtocolRedirect
		metadata.Source = M.SocksaddrFromNet(conn.RemoteAddr()).Unwrap()
		destination, err := control.GetOriginalDestination(conn)
		if err != nil {
			_ = conn.SetLinger(0)
			_ = conn.Close()
			s.logger.Error("process connection from ", metadata.Source, ": invalid connection: ", err)
			continue
		}
		metadata.Destination = M.SocksaddrFromNetIP(destination).Unwrap()
		go s.handler.NewConnection(s.ctx, conn, metadata)
	}
}
