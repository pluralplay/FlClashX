package tun

import (
	"net/netip"
	"time"

	"github.com/metacubex/sing/common/buf"
	"github.com/metacubex/sing/common/cache"
)

type DirectRouteDestination interface {
	WritePacket(packet *buf.Buffer) error
	Close() error
	IsClosed() bool
}

type DirectRouteSession struct {
	// IPVersion uint8
	// Network     uint8
	Source      netip.Addr
	Destination netip.Addr
}

type DirectRouteMapping struct {
	status  *cache.LruCache[DirectRouteSession, DirectRouteDestination]
	timeout time.Duration
}

func NewDirectRouteMapping(timeout time.Duration) *DirectRouteMapping {
	status := cache.New[DirectRouteSession, DirectRouteDestination](
		cache.WithSize[DirectRouteSession, DirectRouteDestination](1024),
		cache.WithHealthCheck[DirectRouteSession, DirectRouteDestination](func(session DirectRouteSession, action DirectRouteDestination) bool {
			if action != nil {
				return !action.IsClosed()
			}
			return true
		}),
		cache.WithEvict[DirectRouteSession, DirectRouteDestination](func(session DirectRouteSession, action DirectRouteDestination) {
			if action != nil {
				action.Close()
			}
		}),
		cache.WithUpdateAgeOnGet[DirectRouteSession, DirectRouteDestination](),
		cache.WithAge[DirectRouteSession, DirectRouteDestination](int64(timeout.Seconds())),
	)
	return &DirectRouteMapping{status, timeout}
}

func (m *DirectRouteMapping) Lookup(session DirectRouteSession, constructor func(timeout time.Duration) (DirectRouteDestination, error)) (DirectRouteDestination, error) {
	var (
		created DirectRouteDestination
		err     error
	)
	action, _, ok := m.status.LoadOrStoreEx(session, func() (DirectRouteDestination, bool) {
		created, err = constructor(m.timeout)
		return created, err == nil
	})
	if !ok {
		return nil, err
	}
	return action, nil
}
