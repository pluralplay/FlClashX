package tun

import (
	"net"
	"net/netip"
	"os"
	"sync"
	"time"

	"github.com/metacubex/sing/common/buf"
	"github.com/metacubex/sing/common/control"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
	"github.com/metacubex/sing/common/x/list"

	"golang.org/x/net/route"
	"golang.org/x/sys/unix"
)

type networkUpdateMonitor struct {
	access          sync.Mutex
	callbacks       list.List[NetworkUpdateCallback]
	routeSocketFile *os.File
	closeOnce       sync.Once
	done            chan struct{}
	logger          logger.Logger
}

func NewNetworkUpdateMonitor(logger logger.Logger) (NetworkUpdateMonitor, error) {
	return &networkUpdateMonitor{
		logger: logger,
		done:   make(chan struct{}),
	}, nil
}

func (m *networkUpdateMonitor) Start() error {
	go m.loopUpdate()
	return nil
}

func (m *networkUpdateMonitor) loopUpdate() {
	for {
		select {
		case <-m.done:
			return
		default:
		}
		err := m.loopUpdate0()
		if err != nil {
			m.logger.Error("listen network update: ", err)
			return
		}
	}
}

func (m *networkUpdateMonitor) loopUpdate0() error {
	routeSocket, err := unix.Socket(unix.AF_ROUTE, unix.SOCK_RAW, 0)
	if err != nil {
		return err
	}
	err = unix.SetNonblock(routeSocket, true)
	if err != nil {
		unix.Close(routeSocket)
		return err
	}
	routeSocketFile := os.NewFile(uintptr(routeSocket), "route")
	defer routeSocketFile.Close()
	m.routeSocketFile = routeSocketFile
	m.loopUpdate1(routeSocketFile)
	return nil
}

func (m *networkUpdateMonitor) loopUpdate1(routeSocketFile *os.File) {
	buffer := buf.NewPacket()
	defer buffer.Release()
	done := make(chan struct{})
	go func() {
		select {
		case <-m.done:
			routeSocketFile.Close()
		case <-done:
		}
	}()
	n, err := routeSocketFile.Read(buffer.FreeBytes())
	close(done)
	if err != nil {
		return
	}
	buffer.Truncate(n)
	messages, err := route.ParseRIB(route.RIBTypeRoute, buffer.Bytes())
	if err != nil {
		return
	}
	for _, message := range messages {
		if _, isRouteMessage := message.(*route.RouteMessage); isRouteMessage {
			m.emit()
			return
		}
	}
}

func (m *networkUpdateMonitor) Close() error {
	m.closeOnce.Do(func() {
		close(m.done)
	})
	return nil
}

func (m *defaultInterfaceMonitor) checkUpdate() error {
	var (
		defaultInterface *control.Interface
		err              error
	)
	if m.underNetworkExtension {
		defaultInterface, err = m.getDefaultInterfaceBySocket()
		if err != nil {
			return err
		}
	} else {
		ribMessage, err := route.FetchRIB(unix.AF_UNSPEC, route.RIBTypeRoute, 0)
		if err != nil {
			return err
		}
		routeMessages, err := route.ParseRIB(route.RIBTypeRoute, ribMessage)
		if err != nil {
			return err
		}
		for _, rawRouteMessage := range routeMessages {
			routeMessage := rawRouteMessage.(*route.RouteMessage)
			if len(routeMessage.Addrs) <= unix.RTAX_NETMASK {
				continue
			}
			destination, isIPv4Destination := routeMessage.Addrs[unix.RTAX_DST].(*route.Inet4Addr)
			if !isIPv4Destination {
				continue
			}
			if destination.IP != netip.IPv4Unspecified().As4() {
				continue
			}
			mask, isIPv4Mask := routeMessage.Addrs[unix.RTAX_NETMASK].(*route.Inet4Addr)
			if !isIPv4Mask {
				continue
			}
			ones, _ := net.IPMask(mask.IP[:]).Size()
			if ones != 0 {
				continue
			}
			routeInterface, err := m.interfaceFinder.ByIndex(routeMessage.Index)
			if err != nil {
				return err
			}
			if routeMessage.Flags&unix.RTF_UP == 0 {
				continue
			}
			if routeMessage.Flags&unix.RTF_GATEWAY == 0 {
				continue
			}
			// if routeMessage.Flags&unix.RTF_IFSCOPE != 0 {
			//continue
			//}
			if routeInterface.Flags&net.FlagLoopback != 0 {
				continue
			}
			defaultInterface = routeInterface
			break
		}
	}
	if defaultInterface == nil {
		return ErrNoRoute
	}
	newInterface, err := m.interfaceFinder.ByIndex(defaultInterface.Index)
	if err != nil {
		return E.Cause(err, "find updated interface: ", defaultInterface.Name)
	}
	oldInterface := m.defaultInterface.Swap(newInterface)
	if oldInterface != nil && oldInterface.Equals(*newInterface) {
		return nil
	}
	m.emit(newInterface, 0)
	return nil
}

func (m *defaultInterfaceMonitor) getDefaultInterfaceBySocket() (*control.Interface, error) {
	socketFd, err := unix.Socket(unix.AF_INET, unix.SOCK_STREAM, 0)
	if err != nil {
		return nil, E.Cause(err, "create file descriptor")
	}
	defer unix.Close(socketFd)
	go unix.Connect(socketFd, &unix.SockaddrInet4{
		Addr: [4]byte{10, 255, 255, 255},
		Port: 80,
	})
	result := make(chan netip.Addr, 1)
	done := make(chan struct{})
	defer close(done)
	go func() {
		for {
			sockname, sockErr := unix.Getsockname(socketFd)
			if sockErr != nil {
				break
			}
			sockaddr, isInet4Sockaddr := sockname.(*unix.SockaddrInet4)
			if !isInet4Sockaddr {
				break
			}
			addr := netip.AddrFrom4(sockaddr.Addr)
			if addr.IsUnspecified() {
				select {
				case <-done:
					break
				default:
					time.Sleep(10 * time.Millisecond)
					continue
				}
			}
			result <- addr
			break
		}
	}()
	var selectedAddr netip.Addr
	select {
	case selectedAddr = <-result:
	case <-time.After(time.Second):
		return nil, nil
	}
	return m.interfaceFinder.ByAddr(selectedAddr)
}
