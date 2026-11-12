//go:build linux

package tun

import (
	"context"
	"net/netip"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestMipsLinuxGROMergesOutput(t *testing.T) {
	file, err := os.CreateTemp(t.TempDir(), "tun-output")
	require.NoError(t, err)
	defer file.Close()
	device := &NativeTun{tunFile: file, vnetHdr: true, tcpGROTable: newTCPGROTable(), udpGROTable: newUDPGROTable()}
	s := &Mipstack{ctx: context.Background(), tun: device}
	source, target := netip.MustParseAddr("8.8.8.8"), netip.MustParseAddr("198.18.0.2")
	first := tcpPacket(source, target, 100, 200, 16, []byte("abcd"))
	second := tcpPacket(source, target, 104, 200, 16, []byte("efgh"))
	require.NoError(t, s.writePackets([][]byte{first, second}, 0))
	data, err := os.ReadFile(file.Name())
	require.NoError(t, err)
	// A single virtio/IP/TCP header followed by both payloads proves that the
	// batch survived the wrapper and had enough writable tailroom for GRO.
	require.Len(t, data, virtioNetHdrLen+40+8)
	require.Equal(t, "abcdefgh", string(data[virtioNetHdrLen+40:]))
}
