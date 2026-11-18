//go:build linux && !android

package core

import (
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
)

func TestDialOwnerSocket(t *testing.T) {
	const owner = 65534
	const socketEnv = "FLCLASHX_TEST_OWNER_SOCKET"
	if path := os.Getenv(socketEnv); path != "" {
		if os.Getuid() != owner || os.Geteuid() != 0 {
			t.Fatalf("expected real UID %d and effective UID 0, got %d and %d", owner, os.Getuid(), os.Geteuid())
		}
		conn, err := dial(path)
		if err != nil {
			t.Fatal(err)
		}
		defer conn.Close()
		return
	}

	if os.Getuid() != 0 || os.Geteuid() != 0 {
		t.Skip("requires root to reproduce the Helper's split credentials")
	}
	setpriv, err := exec.LookPath("setpriv")
	if err != nil {
		t.Skip("requires setpriv to launch the Core without DAC capabilities")
	}
	dir, err := os.MkdirTemp("/tmp", "flclashx-socket-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	if err := os.Chmod(dir, 0o711); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "core.sock")
	listener, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if err := os.Chmod(path, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chown(path, owner, owner); err != nil {
		t.Fatal(err)
	}

	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(setpriv, "--ruid="+strconv.Itoa(owner), "--rgid="+strconv.Itoa(owner),
		"--clear-groups", "--inh-caps=-all", "--ambient-caps=-all",
		"--bounding-set=-dac_override,-dac_read_search,-setuid",
		"--", executable, "-test.run=^TestDialOwnerSocket$")
	cmd.Env = append(os.Environ(), socketEnv+"="+path)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("dial a user-owned 0600 socket with split credentials: %v\n%s", err, output)
	}
}
