//go:build with_gvisor && windows

package tun

import (
	"sync"

	"github.com/metacubex/gvisor/pkg/buffer"
	"github.com/metacubex/gvisor/pkg/tcpip"
	"github.com/metacubex/gvisor/pkg/tcpip/header"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
)

var _ GVisorTun = (*NativeTun)(nil)

func (t *NativeTun) WritePacket(pkt *stack.PacketBuffer) (int, error) {
	return t.write(pkt.AsSlices())
}

func (t *NativeTun) NewEndpoint() (stack.LinkEndpoint, stack.NICOptions, error) {
	return &WintunEndpoint{tun: t}, stack.NICOptions{}, nil
}

var _ stack.LinkEndpoint = (*WintunEndpoint)(nil)

type WintunEndpoint struct {
	tun        *NativeTun
	mu         sync.RWMutex // mu guards dispatcher
	dispatcher stack.NetworkDispatcher
}

func (e *WintunEndpoint) MTU() uint32 {
	return e.tun.options.MTU
}

func (e *WintunEndpoint) SetMTU(mtu uint32) {
}

func (e *WintunEndpoint) MaxHeaderLength() uint16 {
	return 0
}

func (e *WintunEndpoint) LinkAddress() tcpip.LinkAddress {
	return ""
}

func (e *WintunEndpoint) SetLinkAddress(addr tcpip.LinkAddress) {
}

func (e *WintunEndpoint) Capabilities() stack.LinkEndpointCapabilities {
	return stack.CapabilityRXChecksumOffload
}

func (e *WintunEndpoint) Attach(dispatcher stack.NetworkDispatcher) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if dispatcher == nil && e.dispatcher != nil {
		e.dispatcher = nil
		return
	}
	if dispatcher != nil && e.dispatcher == nil {
		e.dispatcher = dispatcher
		go e.dispatchLoop()
	}
}

func (e *WintunEndpoint) dispatchLoop() {
	for {
		var packetBuffer buffer.Buffer
		err := e.tun.ReadFunc(func(b []byte) {
			packetBuffer = buffer.MakeWithData(b)
		})
		if err != nil {
			break
		}
		ihl, ok := packetBuffer.PullUp(0, 1)
		if !ok {
			packetBuffer.Release()
			continue
		}
		var networkProtocol tcpip.NetworkProtocolNumber
		switch header.IPVersion(ihl.AsSlice()) {
		case header.IPv4Version:
			networkProtocol = header.IPv4ProtocolNumber
		case header.IPv6Version:
			networkProtocol = header.IPv6ProtocolNumber
		default:
			e.tun.Write(packetBuffer.Flatten())
			packetBuffer.Release()
			continue
		}
		pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
			Payload:           packetBuffer,
			IsForwardedPacket: true,
		})
		e.mu.RLock()
		dispatcher := e.dispatcher
		e.mu.RUnlock()
		if dispatcher == nil {
			pkt.DecRef()
			return
		}
		dispatcher.DeliverNetworkPacket(networkProtocol, pkt)
		pkt.DecRef()
	}
}

func (e *WintunEndpoint) IsAttached() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.dispatcher != nil
}

func (e *WintunEndpoint) Wait() {
}

func (e *WintunEndpoint) ARPHardwareType() header.ARPHardwareType {
	return header.ARPHardwareNone
}

func (e *WintunEndpoint) AddHeader(buffer *stack.PacketBuffer) {
}

func (e *WintunEndpoint) ParseHeader(ptr *stack.PacketBuffer) bool {
	return true
}

func (e *WintunEndpoint) WritePackets(packetBufferList stack.PacketBufferList) (int, tcpip.Error) {
	var n int
	for _, packet := range packetBufferList.AsSlice() {
		_, err := e.tun.write(packet.AsSlices())
		if err != nil {
			return n, &tcpip.ErrAborted{}
		}
		n++
	}
	return n, nil
}

func (e *WintunEndpoint) Close() {
}

func (e *WintunEndpoint) SetOnCloseAction(f func()) {
}
