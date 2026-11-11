package core

import (
	"runtime/debug"
	"testing"
)

func TestTheCollectorRunsOnlyAgainstTheMemoryLimit(t *testing.T) {
	tuneGC()
	if previous := debug.SetGCPercent(100); previous != -1 {
		t.Errorf("GOGC = %d, want off", previous)
	}
	t.Cleanup(tuneGC)
	if limit := debug.SetMemoryLimit(-1); limit != gcMemoryLimit() {
		t.Errorf("memory limit = %d, want %d", limit, gcMemoryLimit())
	}
	if gcMemoryLimit() < 64<<20 {
		t.Errorf("limit %d leaves the core no room for geodata", gcMemoryLimit())
	}
}
