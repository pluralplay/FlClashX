//go:build linux

package tun

import (
	"os"
	"syscall"
	"unsafe"

	E "github.com/metacubex/sing/common/exceptions"

	"golang.org/x/sys/unix"
)

const (
	// TODO: support TSO with ECN bits
	tunTCPOffloads = unix.TUN_F_CSUM | unix.TUN_F_TSO4 | unix.TUN_F_TSO6
	tunUDPOffloads = unix.TUN_F_USO4 | unix.TUN_F_USO6
)

func checkVNETHDREnabled(fd int, name string) (bool, error) {
	ifr, err := unix.NewIfreq(name)
	if err != nil {
		return false, err
	}
	err = unix.IoctlIfreq(fd, unix.TUNGETIFF, ifr)
	if err != nil {
		return false, os.NewSyscallError("TUNGETIFF", err)
	}
	return ifr.Uint16()&unix.IFF_VNET_HDR != 0, nil
}

func setTCPOffload(fd int) error {
	err := unix.IoctlSetInt(fd, unix.TUNSETOFFLOAD, tunTCPOffloads)
	if err != nil {
		return E.Cause(os.NewSyscallError("TUNSETOFFLOAD", err), "enable offload")
	}
	return nil
}

func setUDPOffload(fd int) error {
	return unix.IoctlSetInt(fd, unix.TUNSETOFFLOAD, tunTCPOffloads|tunUDPOffloads)
}

type ifreqData struct {
	ifrName [unix.IFNAMSIZ]byte
	ifrData uintptr
}

type ethtoolValue struct {
	cmd  uint32
	data uint32
}

//go:linkname ioctlPtr golang.org/x/sys/unix.ioctlPtr
func ioctlPtr(fd int, req uint, arg unsafe.Pointer) (err error)

func checkChecksumOffload(name string, cmd uint32) (bool, error) {
	fd, err := unix.Socket(unix.AF_INET, unix.SOCK_DGRAM, unix.IPPROTO_IP)
	if err != nil {
		return false, err
	}
	defer syscall.Close(fd)
	ifr := ifreqData{}
	copy(ifr.ifrName[:], name)
	data := ethtoolValue{cmd: cmd}
	ifr.ifrData = uintptr(unsafe.Pointer(&data))
	err = ioctlPtr(fd, unix.SIOCETHTOOL, unsafe.Pointer(&ifr))
	if err != nil {
		return false, os.NewSyscallError("SIOCETHTOOL ETHTOOL_GTXCSUM", err)
	}
	return data.data == 0, nil
}

func setChecksumOffload(name string, cmd uint32) error {
	fd, err := unix.Socket(unix.AF_INET, unix.SOCK_DGRAM, unix.IPPROTO_IP)
	if err != nil {
		return err
	}
	defer syscall.Close(fd)
	ifr := ifreqData{}
	copy(ifr.ifrName[:], name)
	data := ethtoolValue{cmd: cmd, data: 0}
	ifr.ifrData = uintptr(unsafe.Pointer(&data))
	err = ioctlPtr(fd, unix.SIOCETHTOOL, unsafe.Pointer(&ifr))
	if err != nil {
		return os.NewSyscallError("SIOCETHTOOL ETHTOOL_STXCSUM", err)
	}
	return nil
}
