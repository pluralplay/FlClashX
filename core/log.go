package core

import (
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/log"
)

var debugStderr = os.Getenv("FLCLASH_CORE_DEBUG") != ""

func logError(format string, args ...any) {
	log.Errorln(format, args...)
	if debugStderr {
		fmt.Fprintf(os.Stderr, "[ERROR] "+format+"\n", args...)
	}
}

// mihomo emits to a subscriber under its own lock and blocks once the buffer
// is full, so the pump reads until the subscription is closed; one that stopped
// early would wedge every logger, the unsubscribe included.
type logPump struct {
	subscription observable.Subscription[log.Event]
	stopped      atomic.Bool
}

func (pump *logPump) run() {
	for event := range pump.subscription {
		event = forwardedLog(event)
		if pump.stopped.Load() || event.LogLevel < log.Level() {
			continue
		}
		sendMessage(LogMessage, event)
	}
}

// mihomo logs its controller closing for the next config at error level, and
// the app shows every error to the user.
func forwardedLog(event log.Event) log.Event {
	if event.LogLevel == log.ERROR && strings.HasSuffix(event.Payload, http.ErrServerClosed.Error()) {
		event.LogLevel = log.INFO
	}
	return event
}

func (pump *logPump) stop() {
	pump.stopped.Store(true)
	log.UnSubscribe(pump.subscription)
}

var (
	logMu     sync.Mutex
	activeLog *logPump
)

func handleStartLog() {
	logMu.Lock()
	defer logMu.Unlock()
	if activeLog != nil {
		activeLog.stop()
	}
	activeLog = &logPump{subscription: log.Subscribe()}
	go activeLog.run()
}

func handleStopLog() {
	logMu.Lock()
	defer logMu.Unlock()
	if activeLog != nil {
		activeLog.stop()
		activeLog = nil
	}
}
