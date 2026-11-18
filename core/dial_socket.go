//go:build !android && !windows

package core

import (
	"fmt"
	"net"
	"strconv"
)

func dial(arg string) (net.Conn, error) {
	_, err := strconv.Atoi(arg)
	if err != nil {
		return dialUnixSocket(arg)
	}
	return net.Dial("tcp", fmt.Sprintf("127.0.0.1:%s", arg))
}
