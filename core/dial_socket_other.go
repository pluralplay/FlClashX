//go:build !android && !windows && !linux

package core

import "net"

func dialUnixSocket(path string) (net.Conn, error) {
	return net.Dial("unix", path)
}
