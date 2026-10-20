//go:build with_gvisor && darwin

package tun

import (
	"github.com/metacubex/gvisor/pkg/tcpip/header"
	"github.com/metacubex/gvisor/pkg/tcpip/link/qdisc/fifo"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
	"github.com/metacubex/sing-tun/internal/fdbased_darwin"
	"github.com/metacubex/sing-tun/internal/rawfile_darwin"

	"golang.org/x/sys/unix"
)

var _ GVisorTun = (*NativeTun)(nil)

func (t *NativeTun) WritePacket(pkt *stack.PacketBuffer) (int, error) {
	views := pkt.AsSlices()
	numIovecs := len(views)
	numIovecs++ // for packetHeaderVec4/6

	// Allocate small iovec arrays on the stack.
	var iovecsArr [8]unix.Iovec
	iovecs := iovecsArr[:0]
	if numIovecs > len(iovecsArr) {
		iovecs = make([]unix.Iovec, 0, numIovecs)
	}

	if pkt.NetworkProtocolNumber == header.IPv4ProtocolNumber {
		iovecs = append(iovecs, packetHeaderVec4)
	} else {
		iovecs = append(iovecs, packetHeaderVec6)
	}
	var dataLen int
	for _, packetSlice := range views {
		dataLen += len(packetSlice)
		iovec := unix.Iovec{
			Base: &packetSlice[0],
		}
		iovec.SetLen(len(packetSlice))
		iovecs = append(iovecs, iovec)
	}
	t.writeAccess.Lock()
	defer t.writeAccess.Unlock()
	errno := rawfile.NonBlockingWriteIovec(t.tunFd, iovecs)
	if errno == 0 {
		return dataLen, nil
	} else {
		return 0, errno
	}
}

func (t *NativeTun) NewEndpoint() (stack.LinkEndpoint, stack.NICOptions, error) {
	ep, err := fdbased.New(&fdbased.Options{
		ProcessorsPerChannel: t.options.EXP_ProcessorsPerChannel,
		FDs:                  []int{t.tunFd},
		MTU:                  t.options.MTU,
		RXChecksumOffload:    true,
		RecvMsgX:             t.options.EXP_RecvMsgX,
		SendMsgX:             t.options.EXP_SendMsgX,
		// The endpoint writes to t.tunFd concurrently with NativeTun's own writers.
		WriteAccess: &t.writeAccess,
	})
	if err != nil {
		return nil, stack.NICOptions{}, err
	}
	return ep, stack.NICOptions{
		QDisc: fifo.New(ep, 1, 1000),
	}, nil
}
