//go:build !windows

package ping

import (
	"golang.org/x/net/ipv6"
)

func parseIPv6ControlMessage(cmsg []byte) (*ipv6.ControlMessage, error) {
	var controlMessage ipv6.ControlMessage
	err := controlMessage.Parse(cmsg)
	if err != nil {
		return nil, err
	}
	return &controlMessage, nil
}
