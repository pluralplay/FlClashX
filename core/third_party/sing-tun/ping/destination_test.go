package ping_test

import (
	"context"
	"errors"
	"net/netip"
	"os"
	"testing"
	"time"

	"github.com/metacubex/sing-tun/internal/gtcpip/header"
	"github.com/metacubex/sing-tun/ping"
	"github.com/metacubex/sing/common/buf"
	"github.com/metacubex/sing/common/logger"

	"github.com/stretchr/testify/require"
	"golang.org/x/exp/slices"
)

func TestIsClosed(t *testing.T) {
	t.Parallel()
	destination, err := ping.ConnectDestination(context.Background(), logger.NOP(), nil, netip.MustParseAddr("1.1.1.1"), nil, 30*time.Second)
	require.NoError(t, err)
	defer destination.Close()
	time.Sleep(1 * time.Second)
	require.False(t, destination.IsClosed())
	destination.Close()
	require.True(t, destination.IsClosed())
}

type channelWriter struct {
	packets chan []byte
}

func (w *channelWriter) WritePacket(packet []byte) error {
	select {
	case w.packets <- slices.Clone(packet):
	default:
	}
	return nil
}

type discardWriter struct{}

func (w discardWriter) WritePacket(packet []byte) error {
	return nil
}

func buildEchoRequest(source, destination netip.Addr, identifier, sequence uint16) *buf.Buffer {
	const totalLen = header.IPv4MinimumSize + header.ICMPv4MinimumSize
	packet := buf.NewSize(totalLen)
	ipHdr := header.IPv4(packet.Extend(totalLen))
	ipHdr.Encode(&header.IPv4Fields{
		TotalLength: totalLen,
		TTL:         64,
		Protocol:    uint8(header.ICMPv4ProtocolNumber),
		SrcAddr:     source,
		DstAddr:     destination,
	})
	ipHdr.SetChecksum(^ipHdr.CalculateChecksum())
	icmpHdr := header.ICMPv4(ipHdr.Payload())
	icmpHdr.SetType(header.ICMPv4Echo)
	icmpHdr.SetIdent(identifier)
	icmpHdr.SetSequence(sequence)
	icmpHdr.SetChecksum(header.ICMPv4Checksum(icmpHdr, 0))
	return packet
}

// darwin unprivileged ICMP sockets and Linux raw sockets receive every
// loopback ICMP packet regardless of the flow it belongs to, so this test
// cannot run parallel to TestPing.
func TestDestinationIdleExpiry(t *testing.T) {
	loopback := netip.MustParseAddr("127.0.0.1")
	writer := &channelWriter{packets: make(chan []byte, 16)}
	destination, err := ping.ConnectDestination(context.Background(), logger.NOP(), nil, loopback, writer, time.Second)
	if errors.Is(err, os.ErrPermission) {
		t.SkipNow()
	}
	require.NoError(t, err)
	defer destination.Close()

	err = destination.WritePacket(buildEchoRequest(loopback, loopback, 0x1111, 1))
	require.NoError(t, err)
	select {
	case packet := <-writer.packets:
		replyIPHdr := header.IPv4(packet)
		replyICMPHdr := header.ICMPv4(replyIPHdr.Payload())
		require.Equal(t, header.ICMPv4EchoReply, replyICMPHdr.Type())
		require.Equal(t, uint16(0x1111), replyICMPHdr.Ident())
	case <-time.After(3 * time.Second):
		t.Fatal("no echo reply received")
	}

	noise, err := ping.ConnectDestination(context.Background(), logger.NOP(), nil, loopback, discardWriter{}, 30*time.Second)
	require.NoError(t, err)
	defer noise.Close()

	deadline := time.Now().Add(5 * time.Second)
	var sequence uint16
	for time.Now().Before(deadline) {
		sequence++
		require.NoError(t, noise.WritePacket(buildEchoRequest(loopback, loopback, 0x2222, sequence)))
		if destination.IsClosed() {
			return
		}
		time.Sleep(150 * time.Millisecond)
	}
	t.Fatal("flow not closed after idle timeout despite unrelated ICMP traffic")
}
