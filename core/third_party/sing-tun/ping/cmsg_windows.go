package ping

import (
	"fmt"
	"unsafe"

	"github.com/metacubex/sing/common"
	"golang.org/x/net/ipv6"
)

const (
	IPV6_HOPLIMIT   = 21
	IPV6_TCLASS     = 39
	IPV6_RECVTCLASS = 40
)

type WSACMSGHDR struct {
	Len   uintptr
	Level int32
	Type  int32
}

var (
	alignedSizeofCmsghdr = (sizeofCmsghdr + cmsgAlignTo - 1) & ^(cmsgAlignTo - 1)
	sizeofCmsghdr        = int(unsafe.Sizeof(WSACMSGHDR{}))
	cmsgAlignTo          = int(unsafe.Sizeof(uintptr(0)))
)

func cmsgAlign(n int) int {
	return (n + cmsgAlignTo - 1) & ^(cmsgAlignTo - 1)
}

func parseIPv6ControlMessage(cmsg []byte) (*ipv6.ControlMessage, error) {
	var controlMessage ipv6.ControlMessage
	for len(cmsg) >= sizeofCmsghdr {
		cmsghdr := (*WSACMSGHDR)(unsafe.Pointer(unsafe.SliceData(cmsg)))
		msgLen := int(cmsghdr.Len)
		msgSize := cmsgAlign(msgLen)
		if msgLen < sizeofCmsghdr || msgSize > len(cmsg) {
			return nil, fmt.Errorf("invalid control message length %d", cmsghdr.Len)
		}
		switch cmsghdr.Type {
		case IPV6_TCLASS:
			controlMessage.TrafficClass = int(common.NativeEndian.Uint32(cmsg[alignedSizeofCmsghdr : alignedSizeofCmsghdr+4]))
		case IPV6_HOPLIMIT:
			controlMessage.HopLimit = int(common.NativeEndian.Uint32(cmsg[alignedSizeofCmsghdr : alignedSizeofCmsghdr+4]))
		}
		cmsg = cmsg[msgSize:]
	}
	return &controlMessage, nil
}
