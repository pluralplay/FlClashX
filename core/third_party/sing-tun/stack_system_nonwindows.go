//go:build !windows

package tun

import (
	"errors"

	"golang.org/x/sys/unix"
)

func fixWindowsFirewall() error {
	return nil
}

func retryableListenError(err error) bool {
	return errors.Is(err, unix.EADDRNOTAVAIL)
}
