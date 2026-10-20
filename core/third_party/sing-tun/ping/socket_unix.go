//go:build unix

package ping

import (
	"net"
	"net/netip"
	"os"
	"runtime"
	"syscall"

	"github.com/metacubex/sing/common/bufio"
	"github.com/metacubex/sing/common/control"
	E "github.com/metacubex/sing/common/exceptions"
	M "github.com/metacubex/sing/common/metadata"

	"golang.org/x/sys/unix"
)

func connect(privileged bool, controlFunc control.Func, destination netip.Addr) (net.Conn, error) {
	var (
		network string
		fd      int
		err     error
	)
	if destination.Is4() {
		network = "ip4" // like std's netFD.ctrlNetwork
		if !privileged {
			fd, err = unix.Socket(unix.AF_INET, unix.SOCK_DGRAM, unix.IPPROTO_ICMP)
		} else {
			fd, err = unix.Socket(unix.AF_INET, unix.SOCK_RAW, unix.IPPROTO_ICMP)
		}
	} else {
		network = "ip6" // like std's netFD.ctrlNetwork
		if !privileged {
			fd, err = unix.Socket(unix.AF_INET6, unix.SOCK_DGRAM, unix.IPPROTO_ICMPV6)
		} else {
			fd, err = unix.Socket(unix.AF_INET6, unix.SOCK_RAW, unix.IPPROTO_ICMPV6)
		}
	}
	if err != nil {
		return nil, E.Cause(err, "socket()")
	}
	file := os.NewFile(uintptr(fd), "datagram-oriented icmp")
	defer file.Close()
	if controlFunc != nil {
		var syscallConn syscall.RawConn
		syscallConn, err = file.SyscallConn()
		if err != nil {
			return nil, err
		}
		err = controlFunc(network, destination.String(), syscallConn)
		if err != nil {
			return nil, err
		}
	}
	if destination.Is4() && (runtime.GOOS == "linux" || runtime.GOOS == "android") {
		//err = unix.SetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_RECVTOS, 1)
		//if err != nil {
		//	return nil, err
		//}
		err = unix.SetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_RECVTTL, 1)
		if err != nil {
			return nil, E.Cause(err, "setsockopt()")
		}
	}
	if destination.Is6() {
		err = unix.SetsockoptInt(fd, unix.IPPROTO_IPV6, unix.IPV6_RECVHOPLIMIT, 1)
		if err != nil {
			return nil, E.Cause(err, "setsockopt()")
		}
		err = unix.SetsockoptInt(fd, unix.IPPROTO_IPV6, unix.IPV6_RECVTCLASS, 1)
		if err != nil {
			return nil, E.Cause(err, "setsockopt()")
		}
	}

	var bindAddress netip.Addr
	if !destination.Is6() {
		bindAddress = netip.AddrFrom4([4]byte{})
	} else {
		bindAddress = netip.AddrFrom16([16]byte{})
	}

	err = unix.Bind(fd, M.AddrPortToSockaddr(netip.AddrPortFrom(bindAddress, 0)))
	if err != nil {
		return nil, err
	}

	if runtime.GOOS == "darwin" && !privileged {
		// When running in NetworkExtension on macOS, write to connected socket results in EPIPE.
		var packetConn net.PacketConn
		packetConn, err = net.FilePacketConn(file)
		if err != nil {
			return nil, err
		}
		return bufio.NewBindPacketConn(packetConn, M.SocksaddrFrom(destination, 0).UDPAddr()), nil
	} else {
		err = unix.Connect(fd, M.AddrPortToSockaddr(netip.AddrPortFrom(destination, 0)))
		if err != nil {
			return nil, err
		}
		var conn net.Conn
		conn, err = net.FileConn(file)
		if err != nil {
			return nil, err
		}
		return conn, nil
	}
}
