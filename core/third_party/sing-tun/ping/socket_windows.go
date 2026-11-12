package ping

import (
	"net"
	"net/netip"
	"syscall"

	"github.com/metacubex/sing/common/control"

	"golang.org/x/sys/windows"
)

func connect(privileged bool, controlFunc control.Func, destination netip.Addr) (net.Conn, error) {
	var dialer net.Dialer
	dialer.Control = controlFunc
	if destination.Is6() {
		dialer.Control = control.Append(dialer.Control, func(network, address string, conn syscall.RawConn) error {
			return control.Raw(conn, func(fd uintptr) error {
				err := windows.SetsockoptInt(windows.Handle(fd), windows.IPPROTO_IPV6, IPV6_HOPLIMIT, 1)
				if err != nil {
					return err
				}
				err = windows.SetsockoptInt(windows.Handle(fd), windows.IPPROTO_IPV6, IPV6_RECVTCLASS, 1)
				if err != nil {
					return err
				}
				return nil
			})
		})
	}
	var network string
	if destination.Is4() {
		network = "ip4:icmp"
	} else {
		network = "ip6:ipv6-icmp"
	}
	return dialer.Dial(network, destination.String())
}
