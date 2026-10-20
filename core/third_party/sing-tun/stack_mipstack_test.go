package tun

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/netip"
	"sync"
	"testing"
	"time"

	mips "github.com/metacubex/mipstack"
	"github.com/metacubex/sing/common/buf"
	"github.com/metacubex/sing/common/logger"
	M "github.com/metacubex/sing/common/metadata"
	N "github.com/metacubex/sing/common/network"
)

type memoryTun struct {
	in, out chan []byte
	done    chan struct{}
	once    sync.Once
}

func newMemoryTun() *memoryTun {
	return &memoryTun{in: make(chan []byte, 32), out: make(chan []byte, 32), done: make(chan struct{})}
}
func (d *memoryTun) Read(p []byte) (int, error) {
	select {
	case packet := <-d.in:
		return copy(p, packet), nil
	case <-d.done:
		return 0, net.ErrClosed
	}
}
func (d *memoryTun) Write(p []byte) (int, error) {
	select {
	case d.out <- append([]byte(nil), p...):
		return len(p), nil
	case <-d.done:
		return 0, net.ErrClosed
	}
}
func (d *memoryTun) Close() error { d.once.Do(func() { close(d.done) }); return nil }

type testHandler struct {
	tcp     func(context.Context, net.Conn, M.Metadata) error
	udp     func(context.Context, netip.AddrPort, *buf.Buffer, M.Metadata, func(N.PacketConn) N.PacketWriter)
	prepare func(DirectRouteContext) (DirectRouteDestination, error)
}

func (h *testHandler) NewConnection(ctx context.Context, c net.Conn, m M.Metadata) error {
	if h.tcp != nil {
		return h.tcp(ctx, c, m)
	}
	return c.Close()
}
func (h *testHandler) NewPacket(ctx context.Context, k netip.AddrPort, b *buf.Buffer, m M.Metadata, init func(N.PacketConn) N.PacketWriter) {
	if h.udp != nil {
		h.udp(ctx, k, b, m, init)
	} else {
		b.Release()
	}
}
func (h *testHandler) PrepareConnection(_ string, _, _ M.Socksaddr, writer DirectRouteContext, _ time.Duration) (DirectRouteDestination, error) {
	if h.prepare != nil {
		return h.prepare(writer)
	}
	return nil, nil
}
func (h *testHandler) NewError(context.Context, error) {}

func testStack(t *testing.T, device Tun, handler *testHandler, modify func(*StackOptions)) *Mipstack {
	t.Helper()
	options := StackOptions{Logger: logger.NOP(), Tun: device, Handler: handler, Context: context.Background(), ICMPTimeout: 50 * time.Millisecond,
		TunOptions: Options{MTU: 1500, Inet4Address: []netip.Prefix{netip.MustParsePrefix("198.18.0.1/30")}, Inet6Address: []netip.Prefix{netip.MustParsePrefix("fd00::1/126")}}}
	if modify != nil {
		modify(&options)
	}
	v, err := NewStack("mips", options)
	if err != nil {
		t.Fatal(err)
	}
	s := v.(*Mipstack)
	if err = s.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close(); _ = device.Close() })
	return s
}

func readPacket(t *testing.T, d *memoryTun) []byte {
	t.Helper()
	select {
	case p := <-d.out:
		return p
	case <-time.After(3 * time.Second):
		t.Fatal("timed out waiting for TUN response")
		return nil
	}
}
func mipsTestChecksum(p []byte) uint16 {
	var sum uint32
	for len(p) >= 2 {
		sum += uint32(binary.BigEndian.Uint16(p))
		p = p[2:]
	}
	if len(p) > 0 {
		sum += uint32(p[0]) << 8
	}
	for sum>>16 != 0 {
		sum = (sum & 65535) + (sum >> 16)
	}
	return ^uint16(sum)
}
func ipPacket(source, target netip.Addr, protocol byte, payload []byte) []byte {
	h := 20
	if source.Is6() {
		h = 40
	}
	p := make([]byte, h+len(payload))
	copy(p[h:], payload)
	if h == 20 {
		p[0] = 0x45
		p[8] = 64
		p[9] = protocol
		binary.BigEndian.PutUint16(p[2:], uint16(len(p)))
		copy(p[12:], source.AsSlice())
		copy(p[16:], target.AsSlice())
		binary.BigEndian.PutUint16(p[10:], mipsTestChecksum(p[:20]))
	} else {
		p[0] = 0x60
		p[6] = protocol
		p[7] = 64
		binary.BigEndian.PutUint16(p[4:], uint16(len(payload)))
		copy(p[8:], source.AsSlice())
		copy(p[24:], target.AsSlice())
	}
	return p
}
func transportPacket(source, target netip.Addr, protocol byte, payload []byte) []byte {
	payload = append([]byte(nil), payload...)
	pseudo := append(append([]byte(nil), source.AsSlice()...), target.AsSlice()...)
	if source.Is4() {
		pseudo = append(pseudo, 0, protocol, byte(len(payload)>>8), byte(len(payload)))
	} else {
		pseudo = append(pseudo, 0, 0, byte(len(payload)>>8), byte(len(payload)), 0, 0, 0, protocol)
	}
	offset := 2
	if protocol == 17 {
		offset = 6
	}
	if protocol == 6 {
		offset = 16
	}
	if protocol == 1 {
		pseudo = nil
	}
	binary.BigEndian.PutUint16(payload[offset:], mipsTestChecksum(append(pseudo, payload...)))
	return ipPacket(source, target, protocol, payload)
}
func udpPacket(source, target netip.Addr, port uint16, data []byte) []byte {
	p := make([]byte, 8+len(data))
	binary.BigEndian.PutUint16(p, 12345)
	binary.BigEndian.PutUint16(p[2:], port)
	binary.BigEndian.PutUint16(p[4:], uint16(len(p)))
	copy(p[8:], data)
	return transportPacket(source, target, 17, p)
}
func tcpPacket(source, target netip.Addr, seq, ack uint32, flags byte, payload []byte) []byte {
	p := make([]byte, 20+len(payload))
	binary.BigEndian.PutUint16(p, 12345)
	binary.BigEndian.PutUint16(p[2:], 443)
	binary.BigEndian.PutUint32(p[4:], seq)
	binary.BigEndian.PutUint32(p[8:], ack)
	p[12] = 5 << 4
	p[13] = flags
	binary.BigEndian.PutUint16(p[14:], 65535)
	copy(p[20:], payload)
	return transportPacket(source, target, 6, p)
}

func TestUDPRepliesFromMultipleDestinations(t *testing.T) {
	for _, pair := range [][2]string{{"198.18.0.1", "8.8.8.8"}, {"fd00::1", "2001:4860:4860::8888"}} {
		t.Run(pair[0], func(t *testing.T) {
			d := newMemoryTun()
			source, target := netip.MustParseAddr(pair[0]), netip.MustParseAddr(pair[1])
			errorsCh := make(chan error, 4)
			h := &testHandler{udp: func(_ context.Context, key netip.AddrPort, b *buf.Buffer, m M.Metadata, init func(N.PacketConn) N.PacketWriter) {
				if key.Addr() != source || m.Source.Addr != source || m.Destination.Addr != target {
					errorsCh <- errors.New("incorrect metadata")
				}
				writer := init(nil) // DNS uses this path, and replies asynchronously.
				go func() { errorsCh <- writer.WritePacket(b, m.Destination) }()
			}}
			s := testStack(t, d, h, nil)
			for _, port := range []uint16{53, 443} {
				d.in <- udpPacket(source, target, port, []byte("hello"))
				response := readPacket(t, d)
				src, dst, proto, ok := mipsPacketAddresses(response)
				if !ok || src != target || dst != source || proto != 17 {
					t.Fatalf("wrong UDP response %x", response)
				}
				h := 20
				if source.Is6() {
					h = 40
				}
				if binary.BigEndian.Uint16(response[h:]) != port || !bytes.Equal(response[h+8:], []byte("hello")) {
					t.Fatalf("wrong UDP payload %x", response)
				}
				if err := <-errorsCh; err != nil {
					t.Fatal(err)
				}
			}
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestTCPHandshakeAndData(t *testing.T) {
	for _, pair := range [][2]string{{"198.18.0.1", "8.8.8.8"}, {"fd00::1", "2001:4860:4860::8888"}} {
		t.Run(pair[0], func(t *testing.T) {
			d := newMemoryTun()
			source, target := netip.MustParseAddr(pair[0]), netip.MustParseAddr(pair[1])
			result := make(chan error, 1)
			h := &testHandler{tcp: func(_ context.Context, c net.Conn, m M.Metadata) error {
				defer c.Close()
				_ = c.SetDeadline(time.Now().Add(2 * time.Second))
				if m.Source.Addr != source || m.Destination.Addr != target {
					result <- errors.New("wrong TCP metadata")
					return nil
				}
				p := make([]byte, 5)
				_, err := io.ReadFull(c, p)
				if err == nil && !bytes.Equal(p, []byte("hello")) {
					err = errors.New("wrong TCP data")
				}
				if err == nil {
					_, err = c.Write([]byte("world"))
				}
				result <- err
				return err
			}}
			testStack(t, d, h, nil)
			d.in <- tcpPacket(source, target, 100, 0, 2, nil)
			synAck := readPacket(t, d)
			offset := 20
			if source.Is6() {
				offset = 40
			}
			if synAck[offset+13]&18 != 18 {
				t.Fatalf("expected SYN ACK: %x", synAck)
			}
			ack := binary.BigEndian.Uint32(synAck[offset+4:]) + 1
			d.in <- tcpPacket(source, target, 101, ack, 16, nil)
			d.in <- tcpPacket(source, target, 101, ack, 24, []byte("hello"))
			for {
				p := readPacket(t, d)
				tcpOffset := int(p[offset+12]>>4) * 4
				if bytes.Contains(p[offset+tcpOffset:], []byte("world")) {
					break
				}
			}
			if err := <-result; err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestICMPEchoAndFilter(t *testing.T) {
	for _, pair := range [][2]string{{"198.18.0.1", "8.8.8.8"}, {"fd00::1", "2001:4860:4860::8888"}} {
		t.Run(pair[0], func(t *testing.T) {
			d := newMemoryTun()
			testStack(t, d, &testHandler{}, nil)
			source, target := netip.MustParseAddr(pair[0]), netip.MustParseAddr(pair[1])
			protocol, kind, reply, offset := byte(1), byte(8), byte(0), 20
			if source.Is6() {
				protocol, kind, reply, offset = 58, 128, 129, 40
			}
			p := transportPacket(source, target, protocol, []byte{kind, 0, 0, 0, 1, 2, 3, 4, 5, 6})
			d.in <- p
			response := readPacket(t, d)
			src, dst, _, ok := mipsPacketAddresses(response)
			if !ok || src != target || dst != source || response[offset] != reply || !bytes.Equal(response[offset+4:], p[offset+4:]) {
				t.Fatalf("wrong echo %x", response)
			}
		})
	}
	d := newMemoryTun()
	testStack(t, d, &testHandler{}, func(o *StackOptions) {
		o.TunOptions.Inet4LoopbackAddress = []netip.Addr{netip.MustParseAddr("10.0.0.1")}
	})
	source := netip.MustParseAddr("198.18.0.1")
	for _, target := range []string{"198.18.0.3", "224.0.0.1", "127.0.0.1"} {
		p := udpPacket(source, netip.MustParseAddr(target), 53, []byte("filter"))
		d.in <- p
		if !bytes.Equal(readPacket(t, d), p) {
			t.Fatal("filter did not reflect packet")
		}
	}
	p := tcpPacket(source, netip.MustParseAddr("10.0.0.1"), 100, 0, 2, nil)
	d.in <- p
	r := readPacket(t, d)
	src, dst, _, _ := mipsPacketAddresses(r)
	if src.String() != "10.0.0.1" || dst != source || mipsTestChecksum(r[:20]) != 0 {
		t.Fatal("invalid loopback rewrite")
	}
}

func TestCloseUnblocksStackOutput(t *testing.T) {
	d := newMemoryTun()
	s := testStack(t, d, &testHandler{}, nil)
	closed := make(chan struct{})
	go func() { _ = s.Close(); close(closed) }()
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("Close waited for TUN Read")
	}
	outputDone := make(chan struct{})
	go func() { s.writeLoop(); close(outputDone) }()
	select {
	case <-outputDone:
	case <-time.After(time.Second):
		t.Fatal("closed stack did not stop output loop")
	}
	// The owner has not closed TUN yet, so its read loop can still reflect packets.
	packet := udpPacket(netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("224.0.0.1"), 53, []byte("reflection"))
	d.in <- packet
	if response := readPacket(t, d); !bytes.Equal(response, packet) {
		t.Fatal("stack close changed TUN reflection")
	}
}

func mipsPacketAddresses(packet []byte) (source, destination netip.Addr, protocol byte, ok bool) {
	parsed, err := mips.ParseIPPacket(packet)
	if err != nil {
		return
	}
	upper, _, err := parsed.UpperLayer()
	return parsed.Source, parsed.Destination, byte(upper), err == nil
}

func TestMipsContextLifecycle(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	d := newMemoryTun()
	s := testStack(t, d, &testHandler{}, func(o *StackOptions) { o.Context = ctx })
	if s.ctx != ctx {
		t.Fatal("stack did not preserve the caller context")
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	if err := s.ctx.Err(); err != nil {
		t.Fatalf("stack close canceled the handler context: %v", err)
	}
	waitMipsStackClosed(t, s)

	cancel()
	d2 := newMemoryTun()
	testStack(t, d2, &testHandler{}, func(o *StackOptions) { o.Context = ctx })
	packet := udpPacket(netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("224.0.0.1"), 53, []byte("reflection"))
	d2.in <- packet
	if response := readPacket(t, d2); !bytes.Equal(response, packet) {
		t.Fatal("caller cancellation changed packet reflection")
	}
}
