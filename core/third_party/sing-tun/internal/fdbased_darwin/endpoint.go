// Copyright 2018 The gVisor Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Package fdbased provides the implementation of data-link layer endpoints
// backed by boundary-preserving file descriptors (e.g., TUN devices,
// seqpacket/datagram sockets).
//
// FD based endpoints can be used in the networking stack by calling New() to
// create a new endpoint, and then passing it as an argument to
// Stack.CreateNIC().
//
// FD based endpoints can use more than one file descriptor to read incoming
// packets. If there are more than one FDs specified and the underlying FD is an
// AF_PACKET then the endpoint will enable FANOUT mode on the socket so that the
// host kernel will consistently hash the packets to the sockets. This ensures
// that packets for the same TCP streams are not reordered.
//
// Similarly if more than one FD's are specified where the underlying FD is not
// AF_PACKET then it's the caller's responsibility to ensure that all inbound
// packets on the descriptors are consistently 5 tuple hashed to one of the
// descriptors to prevent TCP reordering.
//
// Since netstack today does not compute 5 tuple hashes for outgoing packets we
// only use the first FD to write outbound packets. Once 5 tuple hashes for
// all outbound packets are available we will make use of all underlying FD's to
// write outbound packets.
package fdbased

import (
	"fmt"
	"runtime"

	"github.com/metacubex/gvisor/pkg/buffer"
	"github.com/metacubex/gvisor/pkg/sync"
	"github.com/metacubex/gvisor/pkg/tcpip"
	"github.com/metacubex/gvisor/pkg/tcpip/header"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
	"github.com/metacubex/sing-tun/internal/rawfile_darwin"
	"github.com/metacubex/sing/common"

	"golang.org/x/sys/unix"
)

// linkDispatcher reads packets from the link FD and dispatches them to the
// NetworkDispatcher.
type linkDispatcher interface {
	Stop()
	dispatch() (bool, tcpip.Error)
	release()
}

var (
	_ stack.LinkEndpoint = (*endpoint)(nil)
	_ stack.GSOEndpoint  = (*endpoint)(nil)
)

// +stateify savable
type fdInfo struct {
	fd int
}

// +stateify savable
type endpoint struct {
	// fds is the set of file descriptors each identifying one inbound/outbound
	// channel. The endpoint will dispatch from all inbound channels as well as
	// hash outbound packets to specific channels based on the packet hash.
	fds []fdInfo

	// hdrSize specifies the link-layer header size. If set to 0, no header
	// is added/removed; otherwise an ethernet header is used.
	hdrSize int

	// caps holds the endpoint capabilities.
	caps stack.LinkEndpointCapabilities

	// closed is a function to be called when the FD's peer (if any) closes
	// its end of the communication pipe.
	closed func(tcpip.Error) `state:"nosave"`

	inboundDispatchers []linkDispatcher

	mu endpointRWMutex `state:"nosave"`
	// +checklocks:mu
	dispatcher stack.NetworkDispatcher

	// wg keeps track of running goroutines.
	wg sync.WaitGroup `state:"nosave"`

	// maxSyscallHeaderBytes has the same meaning as
	// Options.MaxSyscallHeaderBytes.
	maxSyscallHeaderBytes uintptr

	// writevMaxIovs is the maximum number of iovecs that may be passed to
	// rawfile.NonBlockingWriteIovec, as possibly limited by
	// maxSyscallHeaderBytes. (No analogous limit is defined for
	// rawfile.NonBlockingSendMMsg, since in that case the maximum number of
	// iovecs also depends on the number of mmsghdrs. Instead, if sendBatch
	// encounters a packet whose iovec count is limited by
	// maxSyscallHeaderBytes, it falls back to writing the packet using writev
	// via WritePacket.)
	writevMaxIovs int

	// addr is the address of the endpoint.
	//
	// +checklocks:mu
	addr tcpip.LinkAddress

	// mtu (maximum transmission unit) is the maximum size of a packet.
	// +checklocks:mu
	mtu uint32

	batchSize int
	sendMsgX  bool

	// writeAccess has the same meaning as Options.WriteAccess. Never nil; New
	// substitutes a private mutex when the option is omitted.
	writeAccess sync.Locker
}

// Options specify the details about the fd-based endpoint to be created.
//
// +stateify savable
type Options struct {
	// FDs is a set of FDs used to read/write packets.
	FDs []int

	// MTU is the mtu to use for this endpoint.
	MTU uint32

	// EthernetHeader if true, indicates that the endpoint should read/write
	// ethernet frames instead of IP packets.
	EthernetHeader bool

	// ClosedFunc is a function to be called when an endpoint's peer (if
	// any) closes its end of the communication pipe.
	ClosedFunc func(tcpip.Error)

	// Address is the link address for this endpoint. Only used if
	// EthernetHeader is true.
	Address tcpip.LinkAddress

	// SaveRestore if true, indicates that this NIC capability set should
	// include CapabilitySaveRestore
	SaveRestore bool

	// TXChecksumOffload if true, indicates that this endpoints capability
	// set should include CapabilityTXChecksumOffload.
	TXChecksumOffload bool

	// RXChecksumOffload if true, indicates that this endpoints capability
	// set should include CapabilityRXChecksumOffload.
	RXChecksumOffload bool

	// If MaxSyscallHeaderBytes is non-zero, it is the maximum number of bytes
	// of struct iovec, msghdr, and mmsghdr that may be passed by each host
	// system call.
	MaxSyscallHeaderBytes int

	// InterfaceIndex is the interface index of the underlying device.
	InterfaceIndex int

	// ProcessorsPerChannel is the number of goroutines used to handle packets
	// from each FD.
	ProcessorsPerChannel int

	RecvMsgX bool
	SendMsgX bool

	// WriteAccess is held across writes to the FDs. Anything else writing to them
	// must hold it too. When nil, New substitutes a private mutex.
	WriteAccess sync.Locker
}

// New creates a new fd-based endpoint.
//
// Makes fd non-blocking, but does not take ownership of fd, which must remain
// open for the lifetime of the returned endpoint (until after the endpoint has
// stopped being using and Wait returns).
func New(opts *Options) (stack.LinkEndpoint, error) {
	caps := stack.LinkEndpointCapabilities(0)
	if opts.RXChecksumOffload {
		caps |= stack.CapabilityRXChecksumOffload
	}

	if opts.TXChecksumOffload {
		caps |= stack.CapabilityTXChecksumOffload
	}

	hdrSize := 0
	if opts.EthernetHeader {
		hdrSize = header.EthernetMinimumSize
		caps |= stack.CapabilityResolutionRequired
	}

	if opts.SaveRestore {
		caps |= stack.CapabilitySaveRestore
	}

	if len(opts.FDs) == 0 {
		return nil, fmt.Errorf("opts.FD is empty, at least one FD must be specified")
	}

	if opts.MaxSyscallHeaderBytes < 0 {
		return nil, fmt.Errorf("opts.MaxSyscallHeaderBytes is negative")
	}
	var batchSize int
	if opts.RecvMsgX {
		batchSize = int((512*1024)/(opts.MTU)) + 1
	} else {
		batchSize = 1
	}

	e := &endpoint{
		mtu:                   opts.MTU,
		caps:                  caps,
		closed:                opts.ClosedFunc,
		addr:                  opts.Address,
		hdrSize:               hdrSize,
		maxSyscallHeaderBytes: uintptr(opts.MaxSyscallHeaderBytes),
		writevMaxIovs:         rawfile.MaxIovs,
		batchSize:             batchSize,
		sendMsgX:              opts.SendMsgX,
		writeAccess:           opts.WriteAccess,
	}
	if e.writeAccess == nil {
		e.writeAccess = new(sync.Mutex)
	}
	if e.maxSyscallHeaderBytes != 0 {
		if max := int(e.maxSyscallHeaderBytes / rawfile.SizeofIovec); max < e.writevMaxIovs {
			e.writevMaxIovs = max
		}
	}

	// Create per channel dispatchers.
	for _, fd := range opts.FDs {
		if err := unix.SetNonblock(fd, true); err != nil {
			return nil, fmt.Errorf("unix.SetNonblock(%v) failed: %v", fd, err)
		}

		e.fds = append(e.fds, fdInfo{fd: fd})
		if opts.ProcessorsPerChannel == 0 {
			opts.ProcessorsPerChannel = common.Max(1, runtime.GOMAXPROCS(0)/len(opts.FDs))
		}

		var inboundDispatcher linkDispatcher
		var err error
		if opts.RecvMsgX {
			inboundDispatcher, err = newRecvMMsgDispatcher(fd, e, opts)
			if err != nil {
				return nil, fmt.Errorf("newRecvMMsgDispatcher(%d, %+v) = %v", fd, e, err)
			}
		} else {
			inboundDispatcher, err = newReadVDispatcher(fd, e, opts)
			if err != nil {
				return nil, fmt.Errorf("newReadVDispatcher(%d, %+v) = %v", fd, e, err)
			}
		}
		e.inboundDispatchers = append(e.inboundDispatchers, inboundDispatcher)
	}

	return e, nil
}

// Attach launches the goroutine that reads packets from the file descriptor and
// dispatches them via the provided dispatcher. If one is already attached,
// then nothing happens.
//
// Attach implements stack.LinkEndpoint.Attach.
func (e *endpoint) Attach(dispatcher stack.NetworkDispatcher) {
	e.mu.Lock()

	// nil means the NIC is being removed.
	if dispatcher == nil && e.dispatcher != nil {
		for _, dispatcher := range e.inboundDispatchers {
			dispatcher.Stop()
		}
		e.dispatcher = nil
		// NOTE(gvisor.dev/issue/11456): Unlock e.mu before e.Wait().
		e.mu.Unlock()
		e.Wait()
		return
	}
	defer e.mu.Unlock()
	if dispatcher != nil && e.dispatcher == nil {
		e.dispatcher = dispatcher
		// Link endpoints are not savable. When transportation endpoints are
		// saved, they stop sending outgoing packets and all incoming packets
		// are rejected.
		for i := range e.inboundDispatchers {
			e.wg.Add(1)
			go func(i int) { // S/R-SAFE: See above.
				e.dispatchLoop(e.inboundDispatchers[i])
				e.wg.Done()
			}(i)
		}
	}
}

// IsAttached implements stack.LinkEndpoint.IsAttached.
func (e *endpoint) IsAttached() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.dispatcher != nil
}

// MTU implements stack.LinkEndpoint.MTU.
func (e *endpoint) MTU() uint32 {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.mtu
}

// SetMTU implements stack.LinkEndpoint.SetMTU.
func (e *endpoint) SetMTU(mtu uint32) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.mtu = mtu
}

// Capabilities implements stack.LinkEndpoint.Capabilities.
func (e *endpoint) Capabilities() stack.LinkEndpointCapabilities {
	return e.caps
}

// MaxHeaderLength returns the maximum size of the link-layer header.
func (e *endpoint) MaxHeaderLength() uint16 {
	return uint16(e.hdrSize)
}

// LinkAddress returns the link address of this endpoint.
func (e *endpoint) LinkAddress() tcpip.LinkAddress {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.addr
}

// SetLinkAddress implements stack.LinkEndpoint.SetLinkAddress.
func (e *endpoint) SetLinkAddress(addr tcpip.LinkAddress) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.addr = addr
}

// Wait implements stack.LinkEndpoint.Wait. It waits for the endpoint to stop
// reading from its FD.
func (e *endpoint) Wait() {
	e.wg.Wait()
}

// AddHeader implements stack.LinkEndpoint.AddHeader.
func (e *endpoint) AddHeader(pkt *stack.PacketBuffer) {
	if e.hdrSize > 0 {
		// Add ethernet header if needed.
		eth := header.Ethernet(pkt.LinkHeader().Push(header.EthernetMinimumSize))
		eth.Encode(&header.EthernetFields{
			SrcAddr: pkt.EgressRoute.LocalLinkAddress,
			DstAddr: pkt.EgressRoute.RemoteLinkAddress,
			Type:    pkt.NetworkProtocolNumber,
		})
	}
}

func (e *endpoint) parseHeader(pkt *stack.PacketBuffer) (header.Ethernet, bool) {
	if e.hdrSize <= 0 {
		return nil, true
	}
	hdrBytes, ok := pkt.LinkHeader().Consume(e.hdrSize)
	if !ok {
		return nil, false
	}
	hdr := header.Ethernet(hdrBytes)
	pkt.NetworkProtocolNumber = hdr.Type()
	return hdr, true
}

// parseInboundHeader parses the link header of pkt and returns true if the
// header is well-formed and sent to this endpoint's MAC or the broadcast
// address.
func (e *endpoint) parseInboundHeader(pkt *stack.PacketBuffer, wantAddr tcpip.LinkAddress) bool {
	hdr, ok := e.parseHeader(pkt)
	if !ok || e.hdrSize <= 0 {
		return ok
	}
	dstAddr := hdr.DestinationAddress()
	// Per RFC 9542 2.1 on the least significant bit of the first octet of
	// a MAC address: "If it is zero, the MAC address is unicast. If it is
	// a one, the address is groupcast (multicast or broadcast)." Multicast
	// and broadcast are the same thing to ethernet; they are both sent to
	// everyone.
	return dstAddr == wantAddr || byte(dstAddr[0])&0x01 == 1
}

// ParseHeader implements stack.LinkEndpoint.ParseHeader.
func (e *endpoint) ParseHeader(pkt *stack.PacketBuffer) bool {
	_, ok := e.parseHeader(pkt)
	return ok
}

var (
	packetHeader4 = []byte{0x00, 0x00, 0x00, unix.AF_INET}
	packetHeader6 = []byte{0x00, 0x00, 0x00, unix.AF_INET6}
)

// writePacket writes outbound packets to the file descriptor. If it is not
// currently writable, the packet is dropped.
func (e *endpoint) writePacket(pkt *stack.PacketBuffer) tcpip.Error {
	fdInfo := e.fds[pkt.Hash%uint32(len(e.fds))]
	fd := fdInfo.fd
	var vnetHdrBuf []byte
	if pkt.NetworkProtocolNumber == header.IPv4ProtocolNumber {
		vnetHdrBuf = packetHeader4
	} else {
		vnetHdrBuf = packetHeader6
	}
	views := pkt.AsSlices()
	numIovecs := len(views)
	if len(vnetHdrBuf) != 0 {
		numIovecs++
	}
	if numIovecs > e.writevMaxIovs {
		numIovecs = e.writevMaxIovs
	}

	// Allocate small iovec arrays on the stack.
	var iovecsArr [8]unix.Iovec
	iovecs := iovecsArr[:0]
	if numIovecs > len(iovecsArr) {
		iovecs = make([]unix.Iovec, 0, numIovecs)
	}
	iovecs = rawfile.AppendIovecFromBytes(iovecs, vnetHdrBuf, numIovecs)
	for _, v := range views {
		iovecs = rawfile.AppendIovecFromBytes(iovecs, v, numIovecs)
	}
	if errno := rawfile.NonBlockingWriteIovec(fd, iovecs); errno != 0 {
		return TranslateErrno(errno)
	}
	return nil
}

func (e *endpoint) sendBatch(batchFDInfo fdInfo, pkts []*stack.PacketBuffer) (int, tcpip.Error) {
	// Degrade to writePacket if underlying fd is not a socket.
	if !e.sendMsgX {
		var written int
		var err tcpip.Error
		for written < len(pkts) {
			if err = e.writePacket(pkts[written]); err != nil {
				break
			}
			written++
		}
		return written, err
	}

	// Covers both the sendmsg_x loop below and its writePacket fallback, so
	// writePacket itself must not lock. See tun.NativeTun.writeAccess for why.
	e.writeAccess.Lock()
	defer e.writeAccess.Unlock()

	// Send a batch of packets through batchFD.
	batchFD := batchFDInfo.fd
	mmsgHdrsStorage := make([]rawfile.MsgHdrX, 0, len(pkts))
	packets := 0
	for packets < len(pkts) {
		mmsgHdrs := mmsgHdrsStorage
		batch := pkts[packets:]
		syscallHeaderBytes := uintptr(0)
		for _, pkt := range batch {
			var vnetHdrBuf []byte
			if pkt.NetworkProtocolNumber == header.IPv4ProtocolNumber {
				vnetHdrBuf = packetHeader4
			} else {
				vnetHdrBuf = packetHeader6
			}
			views, offset := pkt.AsViewList()
			var skipped int
			var view *buffer.View
			for view = views.Front(); view != nil && offset >= view.Size(); view = view.Next() {
				offset -= view.Size()
				skipped++
			}

			// We've made it to the usable views.
			numIovecs := views.Len() - skipped
			if len(vnetHdrBuf) != 0 {
				numIovecs++
			}
			if numIovecs > rawfile.MaxIovs {
				numIovecs = rawfile.MaxIovs
			}
			if e.maxSyscallHeaderBytes != 0 {
				syscallHeaderBytes += rawfile.SizeofMsgHdrX + uintptr(numIovecs)*rawfile.SizeofIovec
				if syscallHeaderBytes > e.maxSyscallHeaderBytes {
					// We can't fit this packet into this call to sendmmsg().
					// We could potentially do so if we reduced numIovecs
					// further, but this might incur considerable extra
					// copying. Leave it to the next batch instead.
					break
				}
			}

			// We can't easily allocate iovec arrays on the stack here since
			// they will escape this loop iteration via mmsgHdrs.
			iovecs := make([]unix.Iovec, 0, numIovecs)
			iovecs = rawfile.AppendIovecFromBytes(iovecs, vnetHdrBuf, numIovecs)
			// At most one slice has a non-zero offset.
			iovecs = rawfile.AppendIovecFromBytes(iovecs, view.AsSlice()[offset:], numIovecs)
			for view = view.Next(); view != nil; view = view.Next() {
				iovecs = rawfile.AppendIovecFromBytes(iovecs, view.AsSlice(), numIovecs)
			}

			var mmsgHdr rawfile.MsgHdrX
			mmsgHdr.Msg.Iov = &iovecs[0]
			mmsgHdr.Msg.SetIovlen(len(iovecs))
			// mmsgHdr.DataLen = uint32(len(iovecs))
			mmsgHdrs = append(mmsgHdrs, mmsgHdr)
		}

		if len(mmsgHdrs) == 0 {
			// We can't fit batch[0] into a mmsghdr while staying under
			// e.maxSyscallHeaderBytes. Use WritePacket, which will avoid the
			// mmsghdr (by using writev) and re-buffer iovecs more aggressively
			// if necessary (by using e.writevMaxIovs instead of
			// rawfile.MaxIovs).
			pkt := batch[0]
			if err := e.writePacket(pkt); err != nil {
				return packets, err
			}
			packets++
		} else {
			for len(mmsgHdrs) > 0 {
				sent, errno := rawfile.NonBlockingSendMMsg(batchFD, mmsgHdrs)
				if errno != 0 {
					return packets, TranslateErrno(errno)
				}
				packets += sent
				mmsgHdrs = mmsgHdrs[sent:]
			}
		}
	}

	return packets, nil
}

// WritePackets writes outbound packets to the underlying file descriptors. If
// one is not currently writable, the packet is dropped.
//
// Being a batch API, each packet in pkts should have the following
// fields populated:
//   - pkt.EgressRoute
//   - pkt.GSOOptions
//   - pkt.NetworkProtocolNumber
func (e *endpoint) WritePackets(pkts stack.PacketBufferList) (int, tcpip.Error) {
	// Preallocate to avoid repeated reallocation as we append to batch.
	batch := make([]*stack.PacketBuffer, 0, e.batchSize)
	batchFDInfo := fdInfo{fd: -1}
	sentPackets := 0
	for _, pkt := range pkts.AsSlice() {
		if len(batch) == 0 {
			batchFDInfo = e.fds[pkt.Hash%uint32(len(e.fds))]
		}
		pktFDInfo := e.fds[pkt.Hash%uint32(len(e.fds))]
		if sendNow := pktFDInfo != batchFDInfo; !sendNow {
			batch = append(batch, pkt)
			continue
		}
		n, err := e.sendBatch(batchFDInfo, batch)
		sentPackets += n
		if err != nil {
			return sentPackets, err
		}
		batch = batch[:0]
		batch = append(batch, pkt)
		batchFDInfo = pktFDInfo
	}

	if len(batch) != 0 {
		n, err := e.sendBatch(batchFDInfo, batch)
		sentPackets += n
		if err != nil {
			return sentPackets, err
		}
	}
	return sentPackets, nil
}

// dispatchLoop reads packets from the file descriptor in a loop and dispatches
// them to the network stack.
func (e *endpoint) dispatchLoop(inboundDispatcher linkDispatcher) tcpip.Error {
	for {
		cont, err := inboundDispatcher.dispatch()
		if err != nil || !cont {
			if e.closed != nil {
				e.closed(err)
			}
			inboundDispatcher.release()
			return err
		}
	}
}

// GSOMaxSize implements stack.GSOEndpoint.
func (e *endpoint) GSOMaxSize() uint32 {
	return 0
}

// SupportedGSO implements stack.GSOEndpoint.
func (e *endpoint) SupportedGSO() stack.SupportedGSO {
	return stack.GSONotSupported
}

// ARPHardwareType implements stack.LinkEndpoint.ARPHardwareType.
func (e *endpoint) ARPHardwareType() header.ARPHardwareType {
	if e.hdrSize > 0 {
		return header.ARPHardwareEther
	}
	return header.ARPHardwareNone
}

// Close implements stack.LinkEndpoint.
func (e *endpoint) Close() {}

// SetOnCloseAction implements stack.LinkEndpoint.
func (*endpoint) SetOnCloseAction(func()) {}
