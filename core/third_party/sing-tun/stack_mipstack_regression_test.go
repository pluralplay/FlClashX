package tun

import (
	"bytes"
	"context"
	"encoding/binary"
	"net/netip"
	"testing"
	"time"

	mips "github.com/metacubex/mipstack"
	"github.com/metacubex/sing/common/buf"
	M "github.com/metacubex/sing/common/metadata"
	N "github.com/metacubex/sing/common/network"
	"github.com/stretchr/testify/require"
)

func TestMipsFamiliesWithoutInterfaceAddresses(t *testing.T) {
	for _, configuration := range []string{"none", "ipv4", "ipv6"} {
		for _, family := range []string{"ipv4", "ipv6"} {
			t.Run(configuration+"/"+family, func(t *testing.T) {
				d := newMemoryTun()
				s := testStack(t, d, &testHandler{udp: func(_ context.Context, _ netip.AddrPort, b *buf.Buffer, m M.Metadata, init func(N.PacketConn) N.PacketWriter) {
					if err := init(nil).WritePacket(b, m.Destination); err != nil {
						t.Error(err)
					}
				}}, func(o *StackOptions) {
					if configuration != "ipv4" {
						o.TunOptions.Inet4Address = nil
					}
					if configuration != "ipv6" {
						o.TunOptions.Inet6Address = nil
					}
				})
				source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("8.8.8.8")
				offset := 20
				if family == "ipv6" {
					source, target = netip.MustParseAddr("fd00::2"), netip.MustParseAddr("2001:4860::8888")
					offset = 40
				}
				s.processPackets([][]byte{udpPacket(source, target, 53, []byte("reply"))}, 0)
				packet := readPacket(t, d)
				require.Equal(t, "reply", string(packet[offset+8:]))
				s.processPackets([][]byte{tcpPacket(source, target, 100, 0, 2, nil)}, 0)
				packet = readPacket(t, d)
				require.Equal(t, byte(0x12), packet[offset+13]&0x12)
			})
		}
	}
}

func TestMipsIPv4SmallMTU(t *testing.T) {
	d := newMemoryTun()
	testStack(t, d, &testHandler{}, func(o *StackOptions) {
		o.TunOptions.MTU = 576
		o.TunOptions.Inet6Address = nil
	})
}

func TestMipsUnknownProtocolRejection(t *testing.T) {
	for _, ipv6 := range []bool{false, true} {
		t.Run(map[bool]string{false: "ipv4", true: "ipv6"}[ipv6], func(t *testing.T) {
			d := newMemoryTun()
			s := testStack(t, d, &testHandler{}, nil)
			source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("8.8.8.8")
			kind, code, offset := byte(3), byte(2), 20
			if ipv6 {
				source, target = netip.MustParseAddr("fd00::2"), netip.MustParseAddr("2001:4860::8888")
				kind, code, offset = 4, 1, 40
			}
			input := ipPacket(source, target, 253, bytes.Repeat([]byte{42}, 64))
			s.processPackets([][]byte{input}, 0)
			response := readPacket(t, d)
			require.Equal(t, []byte{kind, code}, response[offset:offset+2])
			parsed, err := mips.ParseIPPacket(response)
			require.NoError(t, err)
			require.Equal(t, source, parsed.Destination)
			require.Equal(t, target, parsed.Source)
			if ipv6 {
				value, err := mips.IPTransportChecksum(parsed.Source, parsed.Destination, 58, parsed.Payload)
				require.NoError(t, err)
				require.Zero(t, value)
				require.Equal(t, uint32(6), binary.BigEndian.Uint32(response[offset+4:]))
			} else {
				require.Zero(t, mipsTestChecksum(parsed.Payload))
			}
			require.True(t, bytes.HasPrefix(input, response[offset+8:]))
			// An ICMP error must not trigger another error; IPv6 No Next Header
			// is also explicitly silent rather than an unknown protocol.
			if ipv6 {
				s.processPackets([][]byte{ipPacket(source, target, 59, nil)}, 0)
			}
			s.processPackets([][]byte{response}, 0)
			select {
			case p := <-d.out:
				t.Fatalf("recursive error: %x", p)
			case <-time.After(30 * time.Millisecond):
			}
		})
	}
}

func TestMipsProcessPacketsOffset(t *testing.T) {
	d := newMemoryTun()
	s := testStack(t, d, &testHandler{}, nil)
	source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("8.8.8.8")
	input := ipPacket(source, target, 253, bytes.Repeat([]byte{42}, 64))
	const packetOffset = 7
	framed := make([]byte, packetOffset+len(input))
	copy(framed[packetOffset:], input)

	s.processPackets([][]byte{framed}, packetOffset)
	response := readPacket(t, d)
	parsed, err := mips.ParseIPPacket(response)
	require.NoError(t, err)
	require.Equal(t, source, parsed.Destination)
	require.Equal(t, target, parsed.Source)
}

func TestMipsLoopbackValidation(t *testing.T) {
	for _, ipv6 := range []bool{false, true} {
		t.Run(map[bool]string{false: "ipv4", true: "ipv6"}[ipv6], func(t *testing.T) {
			d := newMemoryTun()
			source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("198.18.0.9")
			offset := 20
			if ipv6 {
				source, target = netip.MustParseAddr("fd00::2"), netip.MustParseAddr("fd00::9")
				offset = 40
			}
			s := testStack(t, d, &testHandler{}, func(o *StackOptions) {
				if ipv6 {
					o.TunOptions.Inet6LoopbackAddress = []netip.Addr{target}
				} else {
					o.TunOptions.Inet4LoopbackAddress = []netip.Addr{target}
				}
			})
			s.processPackets([][]byte{ipPacket(source, target, 6, []byte{1, 2})}, 0)
			bad := tcpPacket(source, target, 100, 0, 2, nil)
			bad[offset+12] = 0xf0
			s.processPackets([][]byte{bad}, 0)
			bad = tcpPacket(source, target, 100, 0, 2, []byte("bad checksum"))
			bad[len(bad)-1] ^= 1
			s.processPackets([][]byte{bad}, 0)
			good := tcpPacket(source, target, 100, 0, 2, nil)
			if ipv6 {
				good = append(append(append([]byte(nil), good[:40]...), 6, 0, 0, 0, 0, 0, 0, 0), good[40:]...)
				good[6] = 0
				binary.BigEndian.PutUint16(good[4:], uint16(len(good)-40))
			}
			s.processPackets([][]byte{good}, 0)
			response := readPacket(t, d)
			require.Len(t, response, len(good))
			parsed, err := mips.ParseIPPacket(response)
			require.NoError(t, err)
			protocol, payload, err := parsed.UpperLayer()
			require.NoError(t, err)
			value, err := mips.IPTransportChecksum(parsed.Source, parsed.Destination, protocol, payload)
			require.NoError(t, err)
			require.Zero(t, value)
			select {
			case p := <-d.out:
				t.Fatalf("invalid packet reflected: %x", p)
			case <-time.After(30 * time.Millisecond):
			}
		})
	}
}

type ringFullTun struct {
	*windowsTun
	full bool
}

func (d *ringFullTun) Write(p []byte) (int, error) {
	if d.full {
		d.full = false
		return 0, nil
	}
	return d.memoryTun.Write(p)
}
func TestMipsWindowsRingFullKeepsStackAlive(t *testing.T) {
	d := &ringFullTun{windowsTun: &windowsTun{newMemoryTun(), make(chan struct{}, 1)}, full: true}
	s := testStack(t, d, &testHandler{}, nil)
	packet := udpPacket(netip.MustParseAddr("198.18.0.1"), netip.MustParseAddr("224.0.0.1"), 53, nil)
	s.processPackets([][]byte{packet}, 0)
	s.processPackets([][]byte{packet}, 0)
	require.Equal(t, packet, readPacket(t, d.memoryTun))
}

type batchLinuxTun struct {
	*linuxTun
	counts []int
}

func (d *batchLinuxTun) BatchWrite(p [][]byte, offset int) (int, error) {
	d.counts = append(d.counts, len(p))
	return d.linuxTun.BatchWrite(p, offset)
}

type directBatchLinuxTun struct {
	*linuxTun
	received [][]byte
}

func (d *directBatchLinuxTun) BatchWrite(p [][]byte, offset int) (int, error) {
	d.received = p
	for _, packet := range p {
		if _, err := d.memoryTun.Write(packet[offset:]); err != nil {
			return 0, err
		}
	}
	return len(p), nil
}

func TestMipsOutputUsesOffsetBuffers(t *testing.T) {
	const offset = 12
	d := &directBatchLinuxTun{linuxTun: &linuxTun{newMemoryTun(), 10}}
	s := &Mipstack{tun: d}
	payload := ipPacket(netip.MustParseAddr("8.8.8.8"), netip.MustParseAddr("198.18.0.2"), 253, []byte("direct"))
	buffer := make([]byte, offset+len(payload))
	copy(buffer[offset:], payload)

	require.NoError(t, s.writePackets([][]byte{buffer}, offset))
	require.Len(t, d.received, 1)
	if &d.received[0][0] != &buffer[0] {
		t.Fatal("output path copied an already framed packet")
	}
	require.Equal(t, payload, readPacket(t, d.memoryTun))
}

type batchDarwinTun struct {
	*darwinTun
	counts []int
}

func (d *batchDarwinTun) BatchWrite(p []*buf.Buffer) error {
	d.counts = append(d.counts, len(p))
	return d.darwinTun.BatchWrite(p)
}
func TestMipsOutputBatching(t *testing.T) {
	packets := [][]byte{ipPacket(netip.MustParseAddr("8.8.8.8"), netip.MustParseAddr("198.18.0.2"), 253, []byte{1})}
	packets = append(packets, packets[0], packets[0])
	t.Run("linux", func(t *testing.T) {
		d := &batchLinuxTun{linuxTun: &linuxTun{newMemoryTun(), 10}}
		s := testStack(t, d, &testHandler{}, nil)
		require.NoError(t, s.writePackets(packets, 0))
		require.Equal(t, []int{3}, d.counts)
		for range packets {
			require.Equal(t, packets[0], readPacket(t, d.memoryTun))
		}
	})
	t.Run("darwin", func(t *testing.T) {
		d := &batchDarwinTun{darwinTun: &darwinTun{newMemoryTun()}}
		s := testStack(t, d, &testHandler{}, nil)
		require.NoError(t, s.writePackets(packets, 0))
		require.Empty(t, d.counts, "Darwin output must not use shared batch descriptors")
		for range packets {
			require.Equal(t, packets[0], readPacket(t, d.memoryTun))
		}
	})
}

func TestMipsProcessPacketsInPlaceBatching(t *testing.T) {
	d := &batchLinuxTun{linuxTun: &linuxTun{newMemoryTun(), 10}}
	s := testStack(t, d, &testHandler{}, nil)
	source := netip.MustParseAddr("198.18.0.2")
	multicast := netip.MustParseAddr("224.0.0.1")
	first := udpPacket(source, multicast, 53, []byte("first"))
	second := udpPacket(source, multicast, 53, []byte("second"))
	stackPacket := udpPacket(source, netip.MustParseAddr("8.8.8.8"), 53, []byte("stack"))
	packets := [][]byte{
		first,
		stackPacket,
		second,
	}

	s.processPackets(packets, 0)

	require.Equal(t, []int{2}, d.counts)
	require.Equal(t, first, readPacket(t, d.memoryTun))
	require.Equal(t, second, readPacket(t, d.memoryTun))
	require.Equal(t, [][]byte{stackPacket, first, second}, packets)
}

func TestMipsLoopbackFragments(t *testing.T) {
	for _, ipv6 := range []bool{false, true} {
		t.Run(map[bool]string{false: "ipv4", true: "ipv6"}[ipv6], func(t *testing.T) {
			source, target := netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("198.18.0.9")
			if ipv6 {
				source, target = netip.MustParseAddr("fd00::2"), netip.MustParseAddr("fd00::9")
			}
			d := newMemoryTun()
			s := testStack(t, d, &testHandler{}, func(o *StackOptions) {
				if ipv6 {
					o.TunOptions.Inet6LoopbackAddress = []netip.Addr{target}
				} else {
					o.TunOptions.Inet4LoopbackAddress = []netip.Addr{target}
				}
			})
			parsed, err := mips.ParseIPPacket(tcpPacket(source, target, 100, 0, 2, bytes.Repeat([]byte{42}, 1600)))
			require.NoError(t, err)
			fragments, err := parsed.MarshalFragments(1280, 123)
			require.NoError(t, err)
			require.Greater(t, len(fragments), 1)
			for _, fragment := range fragments {
				before := append([]byte(nil), fragment...)
				s.processPackets([][]byte{fragment}, 0)
				response := readPacket(t, d)
				reflected, err := mips.ParseIPPacket(response)
				require.NoError(t, err)
				require.Equal(t, target, reflected.Source)
				require.Equal(t, source, reflected.Destination)
				reflected.Source, reflected.Destination = source, target
				original, err := reflected.MarshalRawBinary()
				require.NoError(t, err)
				require.Equal(t, before, original)
			}
		})
	}
}

func TestMipsNonUnicastChecksumValidation(t *testing.T) {
	d := newMemoryTun()
	s := testStack(t, d, &testHandler{}, nil)
	packet := udpPacket(netip.MustParseAddr("198.18.0.2"), netip.MustParseAddr("224.0.0.1"), 53, []byte("reflect"))
	invalid := append([]byte(nil), packet...)
	invalid[10] ^= 1
	s.processPackets([][]byte{invalid}, 0)
	s.processPackets([][]byte{packet}, 0)
	require.Equal(t, packet, readPacket(t, d))
}
