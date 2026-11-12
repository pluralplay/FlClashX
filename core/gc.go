package core

import (
	"runtime"
	"runtime/debug"
)

const (
	gcMemoryLimitMobile  = 128 << 20
	gcMemoryLimitDesktop = 512 << 20
)

// Collecting only near the limit spares a phone the collector's usual minute-by-minute runs.
func tuneGC() {
	debug.SetGCPercent(-1)
	debug.SetMemoryLimit(gcMemoryLimit())
}

func gcMemoryLimit() int64 {
	if runtime.GOOS == "android" || runtime.GOOS == "ios" {
		return gcMemoryLimitMobile
	}
	return gcMemoryLimitDesktop
}

func init() {
	tuneGC()
}
