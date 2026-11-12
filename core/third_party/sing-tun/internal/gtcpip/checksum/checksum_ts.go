//go:build amd64

package checksum

import "github.com/metacubex/sing-tun/internal/tschecksum"

func Checksum(buf []byte, initial uint16) uint16 {
	return tschecksum.Checksum(buf, initial)
}
