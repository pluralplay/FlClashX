package core

import "testing"

func TestAnInactiveHostGetsNoConnectionStreamAndNoDelayWatch(t *testing.T) {
	t.Cleanup(func() {
		handleSetHostActive(true)
		stopDelayWatch()
		currentRequestTraffic.clear()
	})

	currentRequestTraffic.clear()
	handleSetHostActive(false)
	if hostWantsEvents() {
		t.Fatal("an inactive host still wants events")
	}
	onTrackerFound(newPipeTracker(t))
	currentRequestTraffic.mu.Lock()
	watched := len(currentRequestTraffic.requests)
	currentRequestTraffic.mu.Unlock()
	if watched != 0 {
		t.Fatalf("%d requests watched for an inactive host, want none", watched)
	}
	startDelayWatch()
	delayWatcher.mu.Lock()
	running := delayWatcher.cancel != nil
	delayWatcher.mu.Unlock()
	if running {
		t.Fatal("the delay watch runs for an inactive host")
	}

	handleSetHostActive(true)
	if !hostWantsEvents() && hasEventListener() {
		t.Fatal("an active host wants events again")
	}
}
