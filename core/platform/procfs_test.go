//go:build linux

package platform

import (
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const procHeader = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"

// withProcNet serves files, each a list of "local_address uid [rem_address]"
// rows, as /proc/net, keyed by name (udp, udp6, tcp, tcp6).
func withProcNet(t *testing.T, files map[string][]string) {
	t.Helper()
	dir := t.TempDir()
	for name, rows := range files {
		var table strings.Builder
		table.WriteString(procHeader)
		for index, row := range rows {
			local, rest, _ := strings.Cut(row, " ")
			uid, remote, connected := strings.Cut(rest, " ")
			if !connected {
				remote = "00000000:0000"
			}
			table.WriteString("   " + string(rune('0'+index)) + ": " + local + " " + remote +
				" 07 00000000:00000000 00:00000000 00000000 " + uid + " 0 1234\n")
		}
		if err := os.WriteFile(filepath.Join(dir, name), []byte(table.String()), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	previousDir, previousLocal, previousUid := procNetDir, netIndexOfLocal, netIndexOfUid
	procNetDir, netIndexOfLocal, netIndexOfUid = dir+"/", 1, 7
	t.Cleanup(func() {
		procNetDir, netIndexOfLocal, netIndexOfUid = previousDir, previousLocal, previousUid
	})
}

// 198.18.0.1:40000 as a little-endian kernel lists it.
const (
	tunSource     = "010012C6:9C40"
	anyPort40000  = "00000000:9C40"
	any6Port40000 = "00000000000000000000000000000000:9C40"
)

func udpSource() net.Addr {
	return &net.UDPAddr{IP: net.IPv4(198, 18, 0, 1), Port: 40000}
}

func TestAnUnconnectedUdpSocketIsFoundByItsPort(t *testing.T) {
	withProcNet(t, map[string][]string{"udp": {anyPort40000 + " 10123"}})

	if uid := QuerySocketUidFromProcFs(udpSource(), nil); uid != 10123 {
		t.Errorf("uid = %d, want the wildcard-bound socket's 10123", uid)
	}
}

func TestADualStackUdpSocketIsFoundByItsPort(t *testing.T) {
	withProcNet(t, map[string][]string{"udp6": {any6Port40000 + " 10300"}})

	if uid := QuerySocketUidFromProcFs(udpSource(), nil); uid != 10300 {
		t.Errorf("uid = %d, want the dual-stack socket's 10300", uid)
	}
}

func TestTheSocketBoundToTheSourceItselfWins(t *testing.T) {
	withProcNet(t, map[string][]string{
		"udp6": {any6Port40000 + " 10300"},
		"udp":  {anyPort40000 + " 10123", tunSource + " 10200"},
	})

	if uid := QuerySocketUidFromProcFs(udpSource(), nil); uid != 10200 {
		t.Errorf("uid = %d, want the exactly bound socket's 10200", uid)
	}
}

func TestATcpListenerOnTheSamePortIsNotTheOwner(t *testing.T) {
	withProcNet(t, map[string][]string{"tcp": {anyPort40000 + " 10123"}})
	source := &net.TCPAddr{IP: net.IPv4(198, 18, 0, 1), Port: 40000}

	if uid := QuerySocketUidFromProcFs(source, nil); uid != -1 {
		t.Errorf("uid = %d, want no owner", uid)
	}
}

func TestWildcardSocketsOfDifferentAppsOnOnePortHaveNoOwner(t *testing.T) {
	withProcNet(t, map[string][]string{
		"udp6": {any6Port40000 + " 10300"},
		"udp":  {anyPort40000 + " 10123"},
	})

	if uid := QuerySocketUidFromProcFs(udpSource(), nil); uid != -1 {
		t.Errorf("uid = %d, want no owner among two apps", uid)
	}
}

func TestWildcardSocketsOfOneAppOnOnePortAreItsOwn(t *testing.T) {
	withProcNet(t, map[string][]string{"udp": {anyPort40000 + " 10123", anyPort40000 + " 10123"}})

	if uid := QuerySocketUidFromProcFs(udpSource(), nil); uid != 10123 {
		t.Errorf("uid = %d, want the app's 10123", uid)
	}
}

// 203.0.113.9:443 and 203.0.113.10:443 as a little-endian kernel lists them.
const (
	remoteA = "097100CB:01BB"
	remoteB = "0A7100CB:01BB"
)

func TestAppsSharingAnExactUdpAddressHaveNoOwner(t *testing.T) {
	withProcNet(t, map[string][]string{
		"udp": {tunSource + " 10200", tunSource + " 10201", anyPort40000 + " 10123"},
	})

	if uid := QuerySocketUidFromProcFs(udpSource(), nil); uid != -1 {
		t.Errorf("uid = %d, want no owner between two apps bound to the source", uid)
	}
}

func TestTheSocketConnectedToTheTargetOwnsASharedAddress(t *testing.T) {
	withProcNet(t, map[string][]string{
		"tcp": {tunSource + " 0 " + remoteA, tunSource + " 10200 " + remoteB},
	})
	source := &net.TCPAddr{IP: net.IPv4(198, 18, 0, 1), Port: 40000}
	target := &net.TCPAddr{IP: net.IPv4(203, 0, 113, 10), Port: 443}

	if uid := QuerySocketUidFromProcFs(source, target); uid != 10200 {
		t.Errorf("uid = %d, want 10200, whose socket is connected to the target", uid)
	}
}

// 198.18.0.1:40000 as a v4-mapped address in tcp6.
const mappedSource = "0000000000000000FFFF0000010012C6:9C40"

func TestAConnectedRowInOneTableWinsOverASourceOnlyRowInTheOther(t *testing.T) {
	withProcNet(t, map[string][]string{
		"tcp6": {mappedSource + " 0 0000000000000000FFFF0000097100CB:01BB"},
		"tcp":  {tunSource + " 10200 " + remoteB},
	})
	source := &net.TCPAddr{IP: net.IPv4(198, 18, 0, 1), Port: 40000}
	target := &net.TCPAddr{IP: net.IPv4(203, 0, 113, 10), Port: 443}

	if uid := QuerySocketUidFromProcFs(source, target); uid != 10200 {
		t.Errorf("uid = %d, want 10200, whose v4 socket is connected to the target", uid)
	}
}
