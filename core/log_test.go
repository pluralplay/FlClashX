package core

import (
	"testing"

	"github.com/metacubex/mihomo/log"
)

func TestAControllerClosedForTheNextConfigIsNoErrorToShow(t *testing.T) {
	closed := forwardedLog(log.Event{LogLevel: log.ERROR, Payload: "External controller serve error: http: Server closed"})
	if closed.LogLevel != log.INFO {
		t.Errorf("level = %v, want info for the controller's normal close", closed.LogLevel)
	}
	failed := forwardedLog(log.Event{LogLevel: log.ERROR, Payload: "External controller serve error: listen tcp: address in use"})
	if failed.LogLevel != log.ERROR {
		t.Errorf("level = %v, want a real serve failure kept as an error", failed.LogLevel)
	}
}
