package checksum

import (
	"crypto/rand"
	"testing"

	"github.com/metacubex/sing-tun/internal/tschecksum"
)

func BenchmarkTsChecksum(b *testing.B) {
	packet := make([][]byte, 1000)
	for i := 0; i < 1000; i++ {
		packet[i] = make([]byte, 1500)
		rand.Read(packet[i])
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		tschecksum.Checksum(packet[i%1000], 0)
	}
}

func BenchmarkGChecksum(b *testing.B) {
	packet := make([][]byte, 1000)
	for i := 0; i < 1000; i++ {
		packet[i] = make([]byte, 1500)
		rand.Read(packet[i])
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		calculateChecksum(packet[i%1000], false, 0)
	}
}
