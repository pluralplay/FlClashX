//go:build !amd64

package checksum

// Checksum calculates the checksum (as defined in RFC 1071) of the bytes in the
// given byte array. This function uses an optimized version of the checksum
// algorithm.
//
// The initial checksum must have been computed on an even number of bytes.
func Checksum(buf []byte, initial uint16) uint16 {
	s, _ := calculateChecksum(buf, false, initial)
	return s
}
