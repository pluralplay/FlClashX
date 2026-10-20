package tun

import (
	"bytes"
	"context"
	"encoding/binary"
	"net/netip"
	"testing"
	"time"

	"github.com/metacubex/sing/common/buf"
	M "github.com/metacubex/sing/common/metadata"
	N "github.com/metacubex/sing/common/network"
)

func TestUDPFragmentReassemblyAndMTU(t *testing.T) {
	d := newMemoryTun()
	received := make(chan []byte, 2)
	testStack(t, d, &testHandler{udp: func(_ context.Context, _ netip.AddrPort, b *buf.Buffer, m M.Metadata, init func(N.PacketConn) N.PacketWriter) {
		received <- append([]byte(nil), b.Bytes()...)
		b.Release()
		reply := buf.NewSize(2000)
		_, _ = reply.Write(bytes.Repeat([]byte{42}, 2000))
		_ = init(nil).WritePacket(reply, m.Destination)
	}}, func(o *StackOptions) { o.TunOptions.MTU = 1280 })
	source, target := netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("8.8.8.8")
	payload := bytes.Repeat([]byte{7}, 64)
	packet := udpPacket(source, target, 53, payload)
	for _, part := range []struct {
		offset, end int
		more        bool
	}{{0, 24, true}, {24, len(packet) - 20, false}} {
		fragment := ipPacket(source, target, 17, packet[20+part.offset:20+part.end])
		binary.BigEndian.PutUint16(fragment[4:], 123)
		flags := uint16(part.offset / 8)
		if part.more {
			flags |= 0x2000
		}
		binary.BigEndian.PutUint16(fragment[6:], flags)
		fragment[10], fragment[11] = 0, 0
		binary.BigEndian.PutUint16(fragment[10:], mipsTestChecksum(fragment[:20]))
		d.in <- fragment
	}
	select {
	case got := <-received:
		if !bytes.Equal(got, payload) {
			t.Fatal("wrong reassembled datagram")
		}
	case <-time.After(time.Second):
		t.Fatal("fragments not reassembled")
	}
	var assembled []byte
	for {
		p := readPacket(t, d)
		if len(p) > 1280 || mipsTestChecksum(p[:20]) != 0 {
			t.Fatalf("invalid output fragment %x", p)
		}
		offset := int(binary.BigEndian.Uint16(p[6:])&0x1fff) * 8
		end := offset + len(p) - 20
		if end > len(assembled) {
			assembled = append(assembled, make([]byte, end-len(assembled))...)
		}
		copy(assembled[offset:], p[20:])
		if binary.BigEndian.Uint16(p[6:])&0x2000 == 0 {
			break
		}
	}
	if len(assembled) != 2008 || !bytes.Equal(assembled[8:], bytes.Repeat([]byte{42}, 2000)) {
		t.Fatal("fragmented response lost data")
	}
}

func TestMalformedPacketsDoNotStopStack(t *testing.T) {
	d := newMemoryTun()
	received := make(chan struct{}, 4)
	testStack(t, d, &testHandler{udp: func(_ context.Context, _ netip.AddrPort, b *buf.Buffer, _ M.Metadata, _ func(N.PacketConn) N.PacketWriter) {
		b.Release()
		received <- struct{}{}
	}}, nil)
	p := udpPacket(netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("8.8.8.8"), 53, []byte("valid"))
	d.in <- []byte{0x45}
	bad := append([]byte(nil), p...)
	bad[len(bad)-1] ^= 1
	d.in <- bad
	d.in <- p
	select {
	case <-received:
	case <-time.After(time.Second):
		t.Fatal("valid packet not delivered after malformed traffic")
	}
	select {
	case <-received:
		t.Fatal("invalid checksum reached handler")
	case <-time.After(50 * time.Millisecond):
	}
}

func TestCloseDuringTCPHandshake(t *testing.T) {
	d := newMemoryTun()
	s := testStack(t, d, &testHandler{}, nil)
	d.in <- tcpPacket(netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("8.8.8.8"), 100, 0, 2, nil)
	_ = readPacket(t, d)
	done := make(chan struct{})
	go func() { _ = s.Close(); close(done) }()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("pending handshake prevented shutdown")
	}
}

func TestMipsStartFailure(t *testing.T) {
	d := newMemoryTun()
	defer d.Close()
	base := StackOptions{Context: context.Background(), Tun: d, Handler: &testHandler{}, TunOptions: Options{MTU: 1500, Inet4Address: []netip.Prefix{netip.MustParsePrefix("198.18.0.1/30")}}}
	s, err := NewMipstack(base)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	// Force the dependency's validation failure before any I/O loop starts.
	s.(*Mipstack).mtu = 65536
	if err = s.Start(); err == nil {
		t.Fatal("invalid stack configuration started")
	}
	if s.(*Mipstack).stack != nil {
		t.Fatal("failed startup retained stack")
	}
}
