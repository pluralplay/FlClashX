package tun

import (
	"os"
	"runtime"
	"sync"
	"time"

	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
	"github.com/metacubex/sing/common/x/list"
	"github.com/sagernet/netlink"

	"golang.org/x/sys/unix"
)

type networkUpdateMonitor struct {
	routeUpdate chan netlink.RouteUpdate
	linkUpdate  chan netlink.LinkUpdate
	close       chan struct{}

	access    sync.Mutex
	callbacks list.List[NetworkUpdateCallback]
	logger    logger.Logger
}

var ErrNetlinkBanned = E.New(
	"netlink socket in Android is banned by Google, " +
		"use the root or system (ADB) user to run sing-box, " +
		"or switch to the sing-box Android graphical interface client",
)

func NewNetworkUpdateMonitor(logger logger.Logger) (NetworkUpdateMonitor, error) {
	monitor := &networkUpdateMonitor{
		routeUpdate: make(chan netlink.RouteUpdate, 2),
		linkUpdate:  make(chan netlink.LinkUpdate, 2),
		close:       make(chan struct{}),
		logger:      logger,
	}
	// check is netlink banned by google
	if runtime.GOOS == "android" {
		netlinkSocket, err := unix.Socket(unix.AF_NETLINK, unix.SOCK_DGRAM, unix.NETLINK_ROUTE)
		if err != nil {
			return nil, ErrNetlinkBanned
		}
		err = unix.Bind(netlinkSocket, &unix.SockaddrNetlink{
			Family: unix.AF_NETLINK,
		})
		unix.Close(netlinkSocket)
		if err != nil {
			return nil, ErrNetlinkBanned
		}
	}
	return monitor, nil
}

func (m *networkUpdateMonitor) Start() error {
	err := netlink.RouteSubscribe(m.routeUpdate, m.close)
	if err != nil {
		return err
	}
	err = netlink.LinkSubscribe(m.linkUpdate, m.close)
	if err != nil {
		return err
	}
	go m.loopUpdate()
	return nil
}

func (m *networkUpdateMonitor) loopUpdate() {
	const minDuration = time.Second
	timer := time.NewTimer(minDuration)
	defer timer.Stop()
	for {
		select {
		case <-m.close:
			return
		case <-m.routeUpdate:
		case <-m.linkUpdate:
		}
		m.emit()
		select {
		case <-m.close:
			return
		case <-timer.C:
			timer.Reset(minDuration)
		}
	}
}

func (m *networkUpdateMonitor) Close() error {
	select {
	case <-m.close:
		return os.ErrClosed
	default:
	}
	close(m.close)
	return nil
}
