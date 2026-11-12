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

package fdbased

import (
	"github.com/metacubex/gvisor/pkg/buffer"
	"github.com/metacubex/gvisor/pkg/tcpip"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
	"github.com/metacubex/gvisor/pkg/tcpip/stack/gro"
	"github.com/metacubex/sing-tun/internal/rawfile_darwin"
	"github.com/metacubex/sing-tun/internal/stopfd_darwin"

	"golang.org/x/sys/unix"
)

type iovecBuffer struct {
	mtu    int
	views  []*buffer.View
	iovecs []unix.Iovec `state:"nosave"`
}

func newIovecBuffer(mtu uint32) *iovecBuffer {
	b := &iovecBuffer{
		mtu:    int(mtu),
		views:  make([]*buffer.View, 2),
		iovecs: make([]unix.Iovec, 2),
	}
	return b
}

func (b *iovecBuffer) nextIovecs() []unix.Iovec {
	if b.views[0] == nil {
		b.views[0] = buffer.NewViewSize(4)
		b.iovecs[0] = unix.Iovec{Base: b.views[0].BasePtr()}
		b.iovecs[0].SetLen(4)
	}
	if b.views[1] == nil {
		b.views[1] = buffer.NewViewSize(b.mtu)
		b.iovecs[1] = unix.Iovec{Base: b.views[1].BasePtr()}
		b.iovecs[1].SetLen(b.mtu)
	}
	return b.iovecs
}

// pullBuffer extracts the enough underlying storage from b.buffer to hold n
// bytes. It removes this storage from b.buffer, returns a new buffer
// that holds the storage, and updates pulledIndex to indicate which part
// of b.buffer's storage must be reallocated during the next call to
// nextIovecs.
func (b *iovecBuffer) pullBuffer(n int) buffer.Buffer {
	pulled := buffer.Buffer{}
	pulled.Append(b.views[0])
	pulled.Append(b.views[1])
	pulled.Truncate(int64(n))
	pulled.TrimFront(4)
	b.views[0] = nil
	b.views[1] = nil
	return pulled
}

func (b *iovecBuffer) release() {
	for _, v := range b.views {
		if v != nil {
			v.Release()
			v = nil
		}
	}
}

// readVDispatcher uses readv() system call to read inbound packets and
// dispatches them.
//
// +stateify savable
type readVDispatcher struct {
	stopfd.StopFD
	// fd is the file descriptor used to send and receive packets.
	fd int

	// e is the endpoint this dispatcher is attached to.
	e *endpoint

	// buf is the iovec buffer that contains the packet contents.
	buf *iovecBuffer

	// mgr is the processor goroutine manager.
	mgr *processorManager
}

func newReadVDispatcher(fd int, e *endpoint, opts *Options) (linkDispatcher, error) {
	stopFD, err := stopfd.New()
	if err != nil {
		return nil, err
	}
	d := &readVDispatcher{
		StopFD: stopFD,
		fd:     fd,
		e:      e,
	}
	d.buf = newIovecBuffer(opts.MTU)
	d.mgr = newProcessorManager(opts, e)
	d.mgr.start()
	return d, nil
}

func (d *readVDispatcher) release() {
	d.buf.release()
	d.mgr.close()
}

// dispatch reads one packet from the file descriptor and dispatches it.
func (d *readVDispatcher) dispatch() (bool, tcpip.Error) {
	n, errno := rawfile.BlockingReadvUntilStopped(d.ReadFD, d.fd, d.buf.nextIovecs())
	if n <= 0 || errno != 0 {
		return false, TranslateErrno(errno)
	}

	payload := d.buf.pullBuffer(n)
	pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
		Payload: payload,
	})
	defer pkt.DecRef()

	d.e.mu.RLock()
	addr := d.e.addr
	d.e.mu.RUnlock()
	if !d.e.parseInboundHeader(pkt, addr) {
		return false, nil
	}
	d.mgr.queuePacket(pkt, d.e.hdrSize > 0)
	d.mgr.wakeReady()
	return true, nil
}

// recvMMsgDispatcher uses the recvmmsg system call to read inbound packets and
// dispatches them.
//
// +stateify savable
type recvMMsgDispatcher struct {
	stopfd.StopFD
	// fd is the file descriptor used to send and receive packets.
	fd int

	// e is the endpoint this dispatcher is attached to.
	e *endpoint

	// bufs is an array of iovec buffers that contain packet contents.
	bufs []*iovecBuffer

	// msgHdrs is an array of MMsgHdr objects where each MMsghdr is used to
	// reference an array of iovecs in the iovecs field defined above.  This
	// array is passed as the parameter to recvmmsg call to retrieve
	// potentially more than 1 packet per unix.
	msgHdrs []rawfile.MsgHdrX `state:"nosave"`

	// pkts is reused to avoid allocations.
	pkts stack.PacketBufferList

	// gro coalesces incoming packets to increase throughput.
	gro gro.GRO

	// mgr is the processor goroutine manager.
	mgr *processorManager
}

func newRecvMMsgDispatcher(fd int, e *endpoint, opts *Options) (linkDispatcher, error) {
	stopFD, err := stopfd.New()
	if err != nil {
		return nil, err
	}
	d := &recvMMsgDispatcher{
		StopFD:  stopFD,
		fd:      fd,
		e:       e,
		bufs:    make([]*iovecBuffer, e.batchSize),
		msgHdrs: make([]rawfile.MsgHdrX, e.batchSize),
	}
	for i := range d.bufs {
		d.bufs[i] = newIovecBuffer(opts.MTU)
	}
	d.gro.Init(false)
	d.mgr = newProcessorManager(opts, e)
	d.mgr.start()

	return d, nil
}

func (d *recvMMsgDispatcher) release() {
	for _, iov := range d.bufs {
		iov.release()
	}
	d.mgr.close()
}

// recvMMsgDispatch reads more than one packet at a time from the file
// descriptor and dispatches it.
func (d *recvMMsgDispatcher) dispatch() (bool, tcpip.Error) {
	// Fill message headers.
	for k := range d.msgHdrs {
		iovecs := d.bufs[k].nextIovecs()
		iovLen := len(iovecs)
		// Cannot clear only the length field. Older versions of the darwin kernel will check whether other data is empty.
		// https://github.com/Darm64/XNU/blob/xnu-2782.40.9/bsd/kern/uipc_syscalls.c#L2026-L2048
		d.msgHdrs[k] = rawfile.MsgHdrX{}
		d.msgHdrs[k].Msg.Iov = &iovecs[0]
		d.msgHdrs[k].Msg.SetIovlen(iovLen)
	}

	nMsgs, errno := rawfile.BlockingRecvMMsgUntilStopped(d.ReadFD, d.fd, d.msgHdrs)
	if errno != 0 {
		return false, TranslateErrno(errno)
	}
	if nMsgs == -1 {
		return false, nil
	}

	// Process each of received packets.

	d.e.mu.RLock()
	addr := d.e.addr
	dsp := d.e.dispatcher
	d.e.mu.RUnlock()

	d.gro.Dispatcher = dsp
	defer d.pkts.Reset()

	for k := 0; k < nMsgs; k++ {
		n := int(d.msgHdrs[k].DataLen)
		payload := d.bufs[k].pullBuffer(n)
		pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
			Payload: payload,
		})
		d.pkts.PushBack(pkt)

		// Mark that this iovec has been processed.
		d.msgHdrs[k].Msg.Iovlen = 0

		if d.e.parseInboundHeader(pkt, addr) {
			pkt.RXChecksumValidated = d.e.caps&stack.CapabilityRXChecksumOffload != 0
			d.mgr.queuePacket(pkt, d.e.hdrSize > 0)
		}
	}
	d.mgr.wakeReady()

	return true, nil
}
