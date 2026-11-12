package tun

import (
	"bytes"
	"errors"
	"net/netip"
	"sync"
	"testing"
	"time"

	mips "github.com/metacubex/mipstack"
	"github.com/metacubex/sing/common/buf"
	"github.com/stretchr/testify/require"
)

type echoDestination struct {
	writer DirectRouteContext
	closed chan struct{}
	once   sync.Once
}

func (d *echoDestination) IsClosed() bool {
	select {
	case <-d.closed:
		return true
	default:
		return false
	}
}
func (d *echoDestination) Close() error { d.once.Do(func() { close(d.closed) }); return nil }
func (d *echoDestination) WritePacket(b *buf.Buffer) error {
	defer b.Release()
	source, target, protocol, _ := mipsPacketAddresses(b.Bytes())
	offset := 20
	kind := byte(0)
	if source.Is6() {
		offset = 40
		kind = 129
	}
	payload := append([]byte(nil), b.Bytes()[offset:]...)
	payload[0] = kind
	payload[2], payload[3] = 0, 0
	packet := transportPacket(target, source, protocol, payload)
	go func() { _ = d.writer.WritePacket(packet) }()
	return nil
}

func TestICMPDirectSessionLifecycle(t *testing.T) {
	for _, mode := range []string{"expire", "closed"} {
		t.Run(mode, func(t *testing.T) {
			d := newMemoryTun()
			created := make(chan *echoDestination, 4)
			h := &testHandler{prepare: func(writer DirectRouteContext) (DirectRouteDestination, error) {
				destination := &echoDestination{writer: writer, closed: make(chan struct{})}
				t.Cleanup(func() { _ = destination.Close() })
				created <- destination
				return destination, nil
			}}
			testStack(t, d, h, func(o *StackOptions) { o.ICMPTimeout = time.Second })
			source, target := netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("8.8.8.8")
			echo := func(sequence byte) {
				d.in <- transportPacket(source, target, 1, []byte{8, 0, 0, 0, 0, 1, 0, sequence})
				packet := readPacket(t, d)
				require.Equal(t, byte(0), packet[20])
				require.Equal(t, sequence, packet[len(packet)-1])
			}
			echo(0)
			destination := <-created
			echo(1)
			select {
			case <-created:
				t.Fatal("ICMP session not reused")
			default:
			}
			if mode == "closed" {
				require.NoError(t, destination.Close())
			} else {
				// DirectRouteMapping expires entries on lookup, in whole seconds.
				time.Sleep(time.Second)
			}
			echo(2)
			select {
			case replacement := <-created:
				require.NotSame(t, destination, replacement)
			default:
				t.Fatal("stale ICMP session reused")
			}
			require.True(t, destination.IsClosed())
		})
	}
}

func TestICMPPolicy(t *testing.T) {
	for _, policy := range []string{"drop", "reset", "fallback"} {
		policy := policy
		t.Run(policy, func(t *testing.T) {
			d := newMemoryTun()
			called := make(chan struct{}, 1)
			h := &testHandler{prepare: func(DirectRouteContext) (DirectRouteDestination, error) {
				called <- struct{}{}
				switch policy {
				case "drop":
					return nil, ErrDrop
				case "reset":
					return nil, ErrReset
				default:
					return nil, errors.New("dial failed")
				}
			}}
			testStack(t, d, h, nil)
			d.in <- transportPacket(netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("8.8.8.8"), 1, []byte{8, 0, 0, 0, 0, 1, 0, 1})
			select {
			case <-called:
			case <-time.After(time.Second):
				t.Fatal("policy not called")
			}
			if policy == "drop" {
				select {
				case p := <-d.out:
					t.Fatalf("drop emitted %x", p)
				case <-time.After(50 * time.Millisecond):
				}
				return
			}
			p := readPacket(t, d)
			want := byte(0)
			if policy == "reset" {
				want = 3
			}
			if p[20] != want {
				t.Fatalf("wrong ICMP policy response %x", p)
			}
		})
	}
}

func TestICMPAdmissionLimitDoesNotBlockInput(t *testing.T) {
	d := newMemoryTun()
	started := make(chan struct{})
	release := make(chan struct{})
	var startOnce sync.Once
	h := &testHandler{prepare: func(DirectRouteContext) (DirectRouteDestination, error) {
		startOnce.Do(func() { close(started) })
		<-release
		return nil, nil
	}}
	s := testStack(t, d, h, nil)
	source := netip.MustParseAddr("198.18.0.2")
	target := netip.MustParseAddr("8.8.8.8")
	packet := transportPacket(source, target, 1, []byte{8, 0, 0, 0, 0, 1, 0, 1})

	// The first request blocks in PrepareConnection. Processing well beyond the
	// admission limit proves packet handling keeps admitting and dropping
	// packets instead of waiting for preparation.
	s.processPackets([][]byte{packet}, 0)
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("ICMP preparation did not start")
	}
	sent := make(chan struct{})
	go func() {
		for i := 0; i < 64; i++ {
			s.processPackets([][]byte{packet}, 0)
		}
		close(sent)
	}()
	select {
	case <-sent:
	case <-time.After(time.Second):
		t.Fatal("packet input blocked while ICMP preparation was stalled")
	}
	deadline := time.After(time.Second)
	for len(s.icmpSlots) < cap(s.icmpSlots) {
		select {
		case <-deadline:
			t.Fatalf("ICMP admission did not fill: %d/%d", len(s.icmpSlots), cap(s.icmpSlots))
		default:
			time.Sleep(time.Millisecond)
		}
	}

	close(release)
	// Exactly the admitted requests produce fallback echo replies. The rest
	// were dropped at admission.
	for i := 0; i < cap(s.icmpSlots); i++ {
		readPacket(t, d)
	}
	select {
	case extra := <-d.out:
		t.Fatalf("excess ICMP request was not dropped: %x", extra)
	case <-time.After(100 * time.Millisecond):
	}
	deadline = time.After(time.Second)
	for len(s.icmpSlots) != 0 {
		select {
		case <-deadline:
			t.Fatalf("ICMP admission slots did not drain: %d remaining", len(s.icmpSlots))
		default:
			time.Sleep(time.Millisecond)
		}
	}

	// Once preparation has completed and the slots drain, a fresh request is
	// admitted again.
	s.processPackets([][]byte{packet}, 0)
	readPacket(t, d)
}

func TestICMPInterfaceAddressBypassesPolicy(t *testing.T) {
	for _, family := range []string{"ipv4", "ipv6"} {
		t.Run(family, func(t *testing.T) {
			source := netip.MustParseAddr("198.18.0.2")
			local := netip.MustParseAddr("198.18.0.1")
			remote := netip.MustParseAddr("8.8.8.8")
			protocol, echo, reply, rejected, offset := byte(1), byte(8), byte(0), byte(3), 20
			if family == "ipv6" {
				source = netip.MustParseAddr("fd00::2")
				local = netip.MustParseAddr("fd00::1")
				remote = netip.MustParseAddr("2001:4860:4860::8888")
				protocol, echo, reply, rejected, offset = 58, 128, 129, 1, 40
			}
			d := newMemoryTun()
			called := make(chan struct{}, 2)
			testStack(t, d, &testHandler{prepare: func(DirectRouteContext) (DirectRouteDestination, error) {
				called <- struct{}{}
				return nil, ErrReset
			}}, nil)
			payload := []byte{echo, 0, 0, 0, 0, 1, 0, 7, 42}
			d.in <- transportPacket(source, local, protocol, payload)
			response := readPacket(t, d)
			src, dst, proto, ok := mipsPacketAddresses(response)
			if !ok || src != local || dst != source || proto != protocol || response[offset] != reply || !bytes.Equal(response[offset+4:], payload[4:]) {
				t.Fatalf("invalid interface echo reply: %x", response)
			}
			select {
			case <-called:
				t.Fatal("interface echo reached routing policy")
			default:
			}
			d.in <- transportPacket(source, remote, protocol, payload)
			response = readPacket(t, d)
			if response[offset] != rejected {
				t.Fatalf("remote echo bypassed reset policy: %x", response)
			}
			select {
			case <-called:
			default:
				t.Fatal("remote echo did not reach routing policy")
			}
		})
	}
}

func TestMipsICMPResetAdministrativelyProhibited(t *testing.T) {
	for _, ipv6 := range []bool{false, true} {
		t.Run(map[bool]string{false: "ipv4", true: "ipv6"}[ipv6], func(t *testing.T) {
			d := newMemoryTun()
			s := testStack(t, d, &testHandler{prepare: func(DirectRouteContext) (DirectRouteDestination, error) { return nil, ErrReset }}, nil)
			source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("8.8.8.8")
			protocol, kind, code, offset, limit := byte(1), byte(8), byte(13), 20, 576
			if ipv6 {
				source, target = netip.MustParseAddr("fd00::2"), netip.MustParseAddr("2001:4860::8888")
				protocol, kind, code, offset, limit = 58, 128, 1, 40, 1280
			}
			payload := make([]byte, 1400)
			payload[0] = kind
			s.processPackets([][]byte{transportPacket(source, target, protocol, payload)}, 0)
			response := readPacket(t, d)
			require.LessOrEqual(t, len(response), limit)
			require.Equal(t, code, response[offset+1])
			if ipv6 {
				require.Equal(t, byte(1), response[offset])
			} else {
				require.Equal(t, byte(3), response[offset])
				require.Zero(t, mipsTestChecksum(response[offset:]))
			}
		})
	}
}

func TestMipsICMPRepliesOnly(t *testing.T) {
	for _, ipv6 := range []bool{false, true} {
		for _, mode := range []string{"fallback", "error", "direct"} {
			t.Run(map[bool]string{false: "ipv4", true: "ipv6"}[ipv6]+"/"+mode, func(t *testing.T) {
				source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("8.8.8.8")
				protocol, echo, replyType := byte(1), byte(8), byte(0)
				if ipv6 {
					source, target = netip.MustParseAddr("fd00::2"), netip.MustParseAddr("2001:4860::8888")
					protocol, echo, replyType = 58, 128, 129
				}
				payload := []byte{echo, 0, 0, 0, 0x12, 0x34, 0x56, 0x78, 42, 43}
				input := transportPacket(source, target, protocol, payload)
				original := append([]byte(nil), input...)
				replyPayload := append([]byte(nil), payload...)
				replyPayload[0] = replyType
				replyPacket := transportPacket(target, source, protocol, replyPayload)
				d := newMemoryTun()
				var writer *mipsICMPWriter
				prepared := make(chan struct{})
				burst := func() {
					results := make(chan error, 4)
					for i := 0; i < 4; i++ {
						go func() { results <- writer.WritePacket(replyPacket) }()
					}
					for i := 0; i < 4; i++ {
						require.NoError(t, <-results)
					}
				}
				s := testStack(t, d, &testHandler{prepare: func(context DirectRouteContext) (DirectRouteDestination, error) {
					writer = context.(*mipsICMPWriter)
					close(prepared)
					require.NotNil(t, writer.responder.IPPacket())
					require.NotNil(t, writer.responder.Message().Payload)
					if mode == "error" {
						return nil, errors.New("dial failed")
					}
					if mode == "fallback" {
						return nil, nil
					}
					// Replies may start before PrepareConnection returns.
					burst()
					destination := &echoDestination{writer: writer, closed: make(chan struct{})}
					t.Cleanup(func() { _ = destination.Close() })
					return destination, nil
				}}, nil)
				s.processPackets([][]byte{input}, 0)
				select {
				case <-prepared:
				case <-time.After(time.Second):
					t.Fatal("ICMP preparation not started")
				}
				require.Equal(t, original, input, "borrowed request was modified")
				for i := range input {
					input[i] = 0 // Simulate the delivery buffer being reused.
				}
				count := 1
				if mode == "direct" {
					burst() // The same writer remains usable after the callback.
					count = 9
				}
				for i := 0; i < count; i++ {
					packet, err := mips.ParseIPPacket(readPacket(t, d))
					require.NoError(t, err)
					message, err := packet.ICMPMessage() // Validates the family-specific checksum.
					require.NoError(t, err)
					require.Equal(t, target, message.Source)
					require.Equal(t, source, message.Destination)
					require.Equal(t, replyType, message.Type)
					require.Equal(t, payload[4:], message.Body)
				}
			})
		}
	}
}
