//go:build linux && !android

package core

import (
	"fmt"
	"net"
	"runtime"

	"golang.org/x/sys/unix"
)

func dialUnixSocket(path string) (net.Conn, error) {
	if !isElevated() {
		return net.Dial("unix", path)
	}
	type dialResult struct {
		conn net.Conn
		err  error
	}
	done := make(chan dialResult)
	go func() {
		// The socket belongs to the real UID. Scope the filesystem UID
		// change to this thread, which Go discards when the goroutine exits.
		runtime.LockOSThread()
		conn, err := dialUnixSocketAsOwner(path)
		done <- dialResult{conn: conn, err: err}
	}()
	result := <-done
	return result.conn, result.err
}

func dialUnixSocketAsOwner(path string) (net.Conn, error) {
	if err := unix.Setfsuid(realUid); err != nil {
		return nil, fmt.Errorf("set Core socket filesystem UID: %w", err)
	}
	// setfsuid reports the previous UID even when the change was refused.
	uid, err := unix.SetfsuidRetUid(-1)
	if err != nil {
		return nil, fmt.Errorf("read Core socket filesystem UID: %w", err)
	}
	if uid != realUid {
		return nil, fmt.Errorf("set Core socket filesystem UID to %d: %w", realUid, unix.EPERM)
	}
	return net.Dial("unix", path)
}
