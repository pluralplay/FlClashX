package ping_test

import (
	"context"
	"net/netip"
	"os"
	"runtime"
	"testing"
	"time"

	"github.com/metacubex/gvisor/pkg/rand"
	"github.com/metacubex/sing-tun/internal/gtcpip/header"
	"github.com/metacubex/sing-tun/ping"
	"github.com/metacubex/sing/common/buf"

	"github.com/stretchr/testify/require"
)

func TestPing(t *testing.T) {
	t.Parallel()
	const addr4 = "127.0.0.1"
	t.Run("ipv4", func(t *testing.T) {
		t.Run("unprivileged", func(t *testing.T) {
			if runtime.GOOS == "windows" {
				t.SkipNow()
			}
			t.Run("read-icmp", func(t *testing.T) {
				testPingIPv4ReadICMP(t, false, addr4)
			})
			t.Run("read-ip", func(t *testing.T) {
				testPingIPv4ReadIP(t, false, addr4)
			})
		})
		t.Run("privileged", func(t *testing.T) {
			if runtime.GOOS != "windows" && os.Getuid() != 0 {
				t.SkipNow()
			}
			t.Run("read-icmp", func(t *testing.T) {
				testPingIPv4ReadICMP(t, true, addr4)
			})
			t.Run("read-ip", func(t *testing.T) {
				testPingIPv4ReadIP(t, true, addr4)
			})
		})
	})
	// const addr6 = "2606:4700:4700::1001"
	const addr6 = "::1"
	t.Run("ipv6", func(t *testing.T) {
		t.Run("unprivileged", func(t *testing.T) {
			if runtime.GOOS == "windows" {
				t.SkipNow()
			}
			t.Run("read-icmp", func(t *testing.T) {
				testPingIPv6ReadICMP(t, false, addr6)
			})
			t.Run("read-ip", func(t *testing.T) {
				testPingIPv6ReadIP(t, false, addr6)
			})
		})
		t.Run("privileged", func(t *testing.T) {
			if runtime.GOOS != "windows" && os.Getuid() != 0 {
				t.SkipNow()
			}
			t.Run("read-icmp", func(t *testing.T) {
				testPingIPv6ReadICMP(t, true, addr6)
			})
			t.Run("read-ip", func(t *testing.T) {
				testPingIPv6ReadIP(t, true, addr6)
			})
		})
	})
}

func testPingIPv4ReadIP(t *testing.T, privileged bool, addr string) {
	conn, err := ping.Connect(context.Background(), privileged, nil, netip.MustParseAddr(addr), 0)
	if runtime.GOOS == "linux" && err != nil && err.Error() == "socket(): permission denied" {
		t.SkipNow()
	}
	require.NoError(t, err)

	request := make(header.ICMPv4, header.ICMPv4MinimumSize)
	request.SetType(header.ICMPv4Echo)
	request.SetIdent(uint16(rand.Uint32()))
	request.SetChecksum(header.ICMPv4Checksum(request, 0))

	err = conn.WriteICMP(buf.As(request).ToOwned())
	require.NoError(t, err)

	conn.SetLocalAddr(netip.MustParseAddr("127.0.0.1"))
	require.NoError(t, conn.SetReadDeadline(time.Now().Add(3*time.Second)))

	response := buf.NewPacket()
	err = conn.ReadIP(response)
	require.NoError(t, err)
	if runtime.GOOS == "linux" && privileged {
		response.Reset()
		err = conn.ReadIP(response)
		require.NoError(t, err)
	}
	ipHdr := header.IPv4(response.Bytes())
	require.NotZero(t, ipHdr.TTL())
	icmpHdr := header.ICMPv4(ipHdr.Payload())
	require.Equal(t, header.ICMPv4EchoReply, icmpHdr.Type())
	require.Equal(t, request.Ident(), icmpHdr.Ident())
}

func testPingIPv4ReadICMP(t *testing.T, privileged bool, addr string) {
	conn, err := ping.Connect(context.Background(), privileged, nil, netip.MustParseAddr(addr), 0)
	if runtime.GOOS == "linux" && err != nil && err.Error() == "socket(): permission denied" {
		t.SkipNow()
	}
	require.NoError(t, err)

	request := make(header.ICMPv4, header.ICMPv4MinimumSize)
	request.SetType(header.ICMPv4Echo)
	request.SetIdent(uint16(rand.Uint32()))
	request.SetChecksum(header.ICMPv4Checksum(request, 0))

	err = conn.WriteICMP(buf.As(request).ToOwned())
	require.NoError(t, err)

	require.NoError(t, conn.SetReadDeadline(time.Now().Add(3*time.Second)))

	response := buf.NewPacket()
	err = conn.ReadICMP(response)
	require.NoError(t, err)

	if runtime.GOOS == "linux" && privileged {
		response.Reset()
		err = conn.ReadICMP(response)
		require.NoError(t, err)
	}

	icmpHdr := header.ICMPv4(response.Bytes())
	require.Equal(t, header.ICMPv4EchoReply, icmpHdr.Type())
	require.Equal(t, request.Ident(), icmpHdr.Ident())
}

func testPingIPv6ReadIP(t *testing.T, privileged bool, addr string) {
	conn, err := ping.Connect(context.Background(), privileged, nil, netip.MustParseAddr(addr), 0)
	if runtime.GOOS == "linux" && err != nil && err.Error() == "socket(): permission denied" {
		t.SkipNow()
	}
	require.NoError(t, err)

	request := make(header.ICMPv6, header.ICMPv6MinimumSize)
	request.SetType(header.ICMPv6EchoRequest)
	request.SetIdent(uint16(rand.Uint32()))

	err = conn.WriteICMP(buf.As(request).ToOwned())
	require.NoError(t, err)

	conn.SetLocalAddr(netip.MustParseAddr("::1"))
	require.NoError(t, conn.SetReadDeadline(time.Now().Add(3*time.Second)))

	response := buf.NewPacket()
	err = conn.ReadIP(response)
	require.NoError(t, err)
	if runtime.GOOS == "darwin" || runtime.GOOS == "linux" && privileged {
		response.Reset()
		err = conn.ReadIP(response)
		require.NoError(t, err)
	}
	ipHdr := header.IPv6(response.Bytes())
	require.NotZero(t, ipHdr.HopLimit())
	icmpHdr := header.ICMPv6(ipHdr.Payload())
	require.Equal(t, header.ICMPv6EchoReply, icmpHdr.Type())
	require.Equal(t, request.Ident(), icmpHdr.Ident())
}

func testPingIPv6ReadICMP(t *testing.T, privileged bool, addr string) {
	conn, err := ping.Connect(context.Background(), privileged, nil, netip.MustParseAddr(addr), 0)
	if runtime.GOOS == "linux" && err != nil && err.Error() == "socket(): permission denied" {
		t.SkipNow()
	}
	require.NoError(t, err)

	request := make(header.ICMPv6, header.ICMPv6MinimumSize)
	request.SetType(header.ICMPv6EchoRequest)
	request.SetIdent(uint16(rand.Uint32()))

	err = conn.WriteICMP(buf.As(request).ToOwned())
	require.NoError(t, err)

	require.NoError(t, conn.SetReadDeadline(time.Now().Add(3*time.Second)))

	response := buf.NewPacket()
	err = conn.ReadICMP(response)
	require.NoError(t, err)
	if runtime.GOOS == "darwin" || runtime.GOOS == "linux" && privileged {
		response.Reset()
		err = conn.ReadICMP(response)
		require.NoError(t, err)
	}
	icmpHdr := header.ICMPv6(response.Bytes())
	require.Equal(t, header.ICMPv6EchoReply, icmpHdr.Type())
	require.Equal(t, request.Ident(), icmpHdr.Ident())
}
