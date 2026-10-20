package tun

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net"
	"net/netip"
	"os"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mipstack"
	"github.com/metacubex/sing/common/buf"
	"github.com/metacubex/sing/common/logger"
	M "github.com/metacubex/sing/common/metadata"
	N "github.com/metacubex/sing/common/network"
)

type linuxTun struct {
	*memoryTun
	headroom int
}

// Check the borrowed receive buffer while Write is still using it.
type borrowedLoopbackTun struct {
	*windowsTun
	input   []byte
	entered chan bool
	resume  chan struct{}
}

func (d *borrowedLoopbackTun) Write(packet []byte) (int, error) {
	d.entered <- &packet[0] == &d.input[0]
	<-d.resume
	return d.memoryTun.Write(packet)
}

func TestMipsLoopbackBorrowedBufferLifetime(t *testing.T) {
	for _, ipv6 := range []bool{false, true} {
		t.Run(map[bool]string{false: "ipv4", true: "ipv6"}[ipv6], func(t *testing.T) {
			source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("198.18.0.9")
			if ipv6 {
				source, target = netip.MustParseAddr("fd00::2"), netip.MustParseAddr("fd00::9")
			}
			packet := tcpPacket(source, target, 100, 0, 2, []byte("borrowed payload"))
			parsed, err := mipstack.ParseIPPacket(packet)
			if err != nil {
				t.Fatal(err)
			}
			parsed.Source, parsed.Destination = target, source
			expected, err := parsed.MarshalRawBinary()
			if err != nil {
				t.Fatal(err)
			}
			padding := []byte{0xaa, 0xbb, 0xcc}
			packet = append(packet, padding...)
			expected = append(expected, padding...)
			d := &borrowedLoopbackTun{
				windowsTun: &windowsTun{newMemoryTun(), make(chan struct{}, 1)},
				input:      packet, entered: make(chan bool, 1), resume: make(chan struct{}),
			}
			s := &Mipstack{tun: d, logger: logger.NOP(), inet4LoopbackAddress: []netip.Addr{target}, inet6LoopbackAddress: []netip.Addr{target}}
			done := make(chan struct{})
			go func() { s.wintunLoop(d); close(done) }()
			t.Cleanup(func() {
				_ = d.Close()
				select {
				case <-d.resume:
				default:
					close(d.resume)
				}
				select {
				case <-done:
				case <-time.After(time.Second):
					t.Error("receive loop did not exit")
				}
			})
			d.in <- packet
			select {
			case same := <-d.entered:
				if !same {
					t.Fatal("reflection allocated a separate packet")
				}
			case <-time.After(time.Second):
				t.Fatal("reflection did not reach Write")
			}
			select {
			case <-d.released:
				t.Fatal("receive buffer released before Write completed")
			default:
			}
			close(d.resume)
			select {
			case <-d.released:
			case <-time.After(time.Second):
				t.Fatal("receive buffer was not released after Write")
			}
			// Release poisons the receive buffer; the completed write must survive.
			if !bytes.Equal(readPacket(t, d.memoryTun), expected) {
				t.Fatal("reflection corrupted the packet or its padding")
			}
		})
	}
}

func (d *linuxTun) FrontHeadroom() int      { return d.headroom }
func (d *linuxTun) BatchSize() int          { return 4 }
func (d *linuxTun) TXChecksumOffload() bool { return false }
func (d *linuxTun) BatchRead(buffers [][]byte, offset int, sizes []int) (int, error) {
	if d.headroom == 0 {
		return 0, errors.New("non-GSO device must use Read")
	}
	if offset != d.headroom {
		return 0, errors.New("wrong read headroom")
	}
	n, err := d.Read(buffers[0][offset:])
	sizes[0] = n
	if err != nil {
		return 0, err
	}
	return 1, nil
}
func (d *linuxTun) BatchWrite(buffers [][]byte, offset int) (int, error) {
	if d.headroom == 0 {
		return 0, errors.New("non-GSO device must use Write")
	}
	if offset != d.headroom {
		return 0, errors.New("wrong write headroom")
	}
	var total int
	for _, p := range buffers {
		n, err := d.Write(p[offset:])
		if err != nil {
			return total, err
		}
		total += n + offset
	}
	return total, nil
}

type windowsTun struct {
	*memoryTun
	released chan struct{}
}

func (d *windowsTun) ReadPacket() ([]byte, func(), error) {
	select {
	case p := <-d.in:
		return p, func() {
			for i := range p {
				p[i] = 0
			}
			d.released <- struct{}{}
		}, nil
	case <-d.done:
		return nil, nil, io.EOF
	}
}

type darwinTun struct{ *memoryTun }

func (d *darwinTun) BatchSize() int { return 4 }

func (d *darwinTun) Read(p []byte) (int, error) {
	n, err := d.memoryTun.Read(p[4:])
	if err != nil {
		return 0, err
	}
	copy(p[:4], []byte{0, 0, 0, 2})
	if p[4]>>4 == 6 {
		p[3] = 30
	}
	return n + 4, nil
}

func (d *darwinTun) Write(p []byte) (int, error) {
	if len(p) < 5 {
		return 0, errors.New("missing Darwin packet header")
	}
	family := byte(2)
	if p[4]>>4 == 6 {
		family = 30
	}
	if !bytes.Equal(p[:4], []byte{0, 0, 0, family}) {
		return 0, errors.New("invalid Darwin packet header")
	}
	n, err := d.memoryTun.Write(p[4:])
	return n + 4, err
}

func (d *darwinTun) BatchRead() ([]*buf.Buffer, error) {
	select {
	case p := <-d.in:
		b := buf.NewSize(len(p))
		_, _ = b.Write(p)
		return []*buf.Buffer{b}, nil
	case <-d.done:
		return nil, io.EOF
	}
}
func (d *darwinTun) BatchWrite(buffers []*buf.Buffer) error {
	for _, b := range buffers {
		if _, err := d.memoryTun.Write(b.Bytes()); err != nil {
			return err
		}
	}
	return nil
}

func TestPlatformPacketIO(t *testing.T) {
	for _, name := range []string{"linux", "linux-gso", "windows", "darwin", "darwin-raw"} {
		t.Run(name, func(t *testing.T) {
			memory := newMemoryTun()
			var device Tun = memory
			var released chan struct{}
			switch name {
			case "linux":
				device = &linuxTun{memory, 0}
			case "linux-gso":
				device = &linuxTun{memory, 10}
			case "windows":
				released = make(chan struct{}, 1)
				device = &windowsTun{memory, released}
			case "darwin", "darwin-raw":
				device = &darwinTun{memory}
			}
			h := &testHandler{udp: func(_ context.Context, _ netip.AddrPort, b *buf.Buffer, m M.Metadata, init func(N.PacketConn) N.PacketWriter) {
				w := init(nil)
				go func() {
					if released != nil {
						<-released
					}
					_ = w.WritePacket(b, m.Destination)
				}()
			}}
			testStack(t, device, h, func(o *StackOptions) { o.TunOptions.EXP_RecvMsgX = name != "darwin-raw" })
			memory.in <- udpPacket(netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("8.8.8.8"), 53, []byte("owned payload"))
			p := readPacket(t, memory)
			if string(p[28:]) != "owned payload" {
				t.Fatalf("buffer ownership violated: %x", p)
			}
		})
	}
}

// Fail one operation, then allow subsequent packets through.
type failedTun struct {
	*memoryTun
	readFailure  error
	writeFailure error
	failed       chan struct{}
}

func (d *failedTun) Read(p []byte) (int, error) {
	if err := d.readFailure; err != nil {
		d.readFailure = nil
		close(d.failed)
		return 0, err
	}
	return d.memoryTun.Read(p)
}

func (d *failedTun) Write(p []byte) (int, error) {
	if err := d.writeFailure; err != nil {
		d.writeFailure = nil
		close(d.failed)
		return 0, err
	}
	return d.memoryTun.Write(p)
}

type failedDarwinTun struct {
	DarwinTUN
	failed       chan struct{}
	writeFailure error
}

func (d *failedDarwinTun) Write(packet []byte) (int, error) {
	if err := d.writeFailure; err != nil {
		d.writeFailure = nil
		close(d.failed)
		return 0, err
	}
	return d.DarwinTUN.Write(packet)
}

func TestMipsIOErrorRecovery(t *testing.T) {
	for _, path := range []string{"read", "write", "darwin-write"} {
		for _, reflected := range []bool{false, true} {
			name := path + "/stack"
			if reflected {
				name = path + "/reflection"
			}
			t.Run(name, func(t *testing.T) {
				memory := newMemoryTun()
				failed := make(chan struct{})
				d := &failedTun{memoryTun: memory, failed: failed}
				var device Tun = d
				switch path {
				case "read":
					d.readFailure = syscall.EINTR
				case "write":
					d.writeFailure = io.ErrShortWrite
				case "darwin-write":
					device = &failedDarwinTun{DarwinTUN: &darwinTun{memory}, failed: failed, writeFailure: syscall.EAGAIN}
				}
				h := &testHandler{udp: func(_ context.Context, _ netip.AddrPort, b *buf.Buffer, m M.Metadata, init func(N.PacketConn) N.PacketWriter) {
					if err := init(nil).WritePacket(b, m.Destination); err != nil {
						t.Error(err)
					}
				}}
				testStack(t, device, h, func(o *StackOptions) { o.TunOptions.EXP_RecvMsgX = true })
				destination := netip.MustParseAddr("8.8.8.8")
				if reflected {
					destination = netip.MustParseAddr("224.0.0.1")
				}
				packet := udpPacket(netip.MustParseAddr("198.18.0.1"), destination, 53, []byte("recovered"))
				if path != "read" {
					memory.in <- packet
				}
				select {
				case <-failed:
				case <-time.After(time.Second):
					t.Fatal("I/O failure was not exercised")
				}
				memory.in <- packet
				response := readPacket(t, memory)
				if !bytes.Equal(response[28:], []byte("recovered")) {
					t.Fatalf("unexpected response: %x", response)
				}
			})
		}
	}
}

func TestMipsDeviceCloseExitsReadLoop(t *testing.T) {
	d := newMemoryTun()
	_ = d.Close()
	s := &Mipstack{tun: d, logger: logger.NOP()}
	done := make(chan struct{})
	go func() { s.readLoop(); close(done) }()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("read loop did not exit")
	}
}

type failedWindowsTun struct {
	*windowsTun
	readFailure error
}

func (d *failedWindowsTun) ReadPacket() ([]byte, func(), error) {
	if err := d.readFailure; err != nil {
		d.readFailure = nil
		return nil, nil, err
	}
	return d.windowsTun.ReadPacket()
}

func TestMipsWindowsReadFailureExitsReadLoop(t *testing.T) {
	d := &failedWindowsTun{
		windowsTun:  &windowsTun{memoryTun: newMemoryTun()},
		readFailure: errors.New("send ring corrupt"),
	}
	t.Cleanup(func() { _ = d.Close() })
	s := &Mipstack{tun: d, logger: logger.NOP()}
	done := make(chan struct{})
	go func() { s.readLoop(); close(done) }()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Windows read loop did not exit")
	}
}

func waitMipsStackClosed(t *testing.T, s *Mipstack) {
	t.Helper()
	result := make(chan error, 1)
	go func() {
		_, err := s.stack.Read([][]byte{make([]byte, s.mtu)}, make([]int, 1), 0)
		result <- err
	}()
	select {
	case err := <-result:
		if !errors.Is(err, net.ErrClosed) && !errors.Is(err, io.EOF) && !errors.Is(err, os.ErrClosed) {
			t.Fatalf("expected closed stack, got %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("stack read was not unblocked by shutdown")
	}
}

// Hold both writes inside the device to expose scratch storage shared by callers.
type overlappingLinuxTun struct {
	*linuxTun
	entered chan struct{}
	release chan struct{}
}

func (d *overlappingLinuxTun) BatchWrite(packets [][]byte, offset int) (int, error) {
	d.entered <- struct{}{}
	<-d.release
	return d.linuxTun.BatchWrite(packets, offset)
}

func TestMipsConcurrentOutputAndReflection(t *testing.T) {
	d := &overlappingLinuxTun{
		linuxTun: &linuxTun{newMemoryTun(), 10},
		entered:  make(chan struct{}, 2),
		release:  make(chan struct{}),
	}
	t.Cleanup(func() { _ = d.Close() })
	s := &Mipstack{tun: d}
	first, second := []byte("stack output"), []byte("reflected packet")
	results := make(chan error, 2)
	go func() {
		results <- s.writePackets([][]byte{first}, 0)
	}()
	go func() { results <- s.writePackets([][]byte{second}, 0) }()
	for i := 0; i < 2; i++ {
		select {
		case <-d.entered:
		case <-time.After(time.Second):
			close(d.release)
			t.Fatal("independent writes were serialized")
		}
	}
	close(d.release)
	for i := 0; i < 2; i++ {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	seen := map[string]bool{string(readPacket(t, d.memoryTun)): true}
	seen[string(readPacket(t, d.memoryTun))] = true
	if !seen[string(first)] || !seen[string(second)] {
		t.Fatalf("concurrent writes corrupted packet storage: %v", seen)
	}
}

type overlappingDarwinTun struct {
	*darwinTun
	entered chan struct{}
	release chan struct{}
}

func (d *overlappingDarwinTun) Write(packet []byte) (int, error) {
	d.entered <- struct{}{}
	<-d.release
	return d.darwinTun.Write(packet)
}

func TestMipsDarwinConcurrentOutputAndReflection(t *testing.T) {
	d := &overlappingDarwinTun{
		darwinTun: &darwinTun{newMemoryTun()},
		entered:   make(chan struct{}, 2),
		release:   make(chan struct{}),
	}
	t.Cleanup(func() { _ = d.Close() })
	s := &Mipstack{tun: d}
	first := ipPacket(netip.MustParseAddr("8.8.8.8"), netip.MustParseAddr("198.18.0.2"), 253, []byte("output"))
	second := ipPacket(netip.MustParseAddr("fd00::1"), netip.MustParseAddr("fd00::2"), 253, []byte("reflection"))
	results := make(chan error, 2)
	go func() {
		results <- s.writePackets([][]byte{first}, 0)
	}()
	go func() { results <- s.writePackets([][]byte{second}, 0) }()
	for i := 0; i < 2; i++ {
		select {
		case <-d.entered:
		case <-time.After(time.Second):
			close(d.release)
			t.Fatal("independent Darwin writes were serialized")
		}
	}
	close(d.release)
	for i := 0; i < 2; i++ {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	seen := map[string]bool{string(readPacket(t, d.memoryTun)): true}
	seen[string(readPacket(t, d.memoryTun))] = true
	if !seen[string(first)] || !seen[string(second)] {
		t.Fatalf("concurrent writes corrupted packet storage: %v", seen)
	}
}
