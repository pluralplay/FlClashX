//go:build !cgo && !android

package core

import (
	"encoding/json"
	"slices"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
)

// stubTun stands in for mihomo's TUN: a test run as root would otherwise open
// one and route the host through it.
func stubTun(t *testing.T, listening bool) *bool {
	t.Helper()
	previousOpen, previousListening := openTun, tunListening
	t.Cleanup(func() { openTun, tunListening = previousOpen, previousListening })
	openTun = func(LC.Tun, constant.Tunnel) {}
	tunListening = func() bool { return listening }
	return &listening
}

func TestATunMihomoCouldNotOpenReachesTheHost(t *testing.T) {
	runningApplies(t)
	listening := stubTun(t, true)
	fake := &fakeConn{}
	previousConn := swapConn(fake)
	defer swapConn(previousConn)

	updateListeners(parsedConfig(t, func(raw *config.RawConfig) { raw.Tun.Enable = true }))
	*listening = false
	updateListeners(parsedConfig(t, func(*config.RawConfig) {}))
	updateListeners(parsedConfig(t, func(raw *config.RawConfig) { raw.Tun.Enable = true }))

	// The state queue keeps order, so the marker arrives after every event before it.
	sendMessage(LoadedMessage, "marker")
	deadline := time.Now().Add(2 * time.Second)
	for {
		var state []Message
		for _, frame := range fake.frames(t) {
			var batch struct {
				Arguments []Message `json:"arguments"`
			}
			if err := json.Unmarshal(frame, &batch); err != nil {
				t.Fatalf("frame is not a message batch: %v", err)
			}
			for _, message := range batch.Arguments {
				if classOfMessage(message) == stateMessageClass {
					state = append(state, message)
				}
			}
		}
		if slices.ContainsFunc(state, func(message Message) bool { return message.Data == "marker" }) {
			failures := slices.DeleteFunc(state, func(message Message) bool { return message.Type != TunFailedMessage })
			if len(failures) != 1 {
				t.Errorf("tunFailed sent %d times, want once, for the TUN that did not open", len(failures))
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("state messages = %v, want the marker sent after the updates", state)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestGetTunFailedAnswersForTheConfigLastApplied(t *testing.T) {
	runningApplies(t)
	listening := stubTun(t, false)
	previous := currentConfig
	t.Cleanup(func() { currentConfig = previous })

	currentConfig = parsedConfig(t, func(raw *config.RawConfig) { raw.Tun.Enable = true })
	if !handleGetTunFailed() {
		t.Error("a TUN the applied config asks for and mihomo did not open is not reported")
	}
	*listening = true
	if handleGetTunFailed() {
		t.Error("an open TUN is reported as failed")
	}
	*listening = false
	currentConfig = parsedConfig(t, func(*config.RawConfig) {})
	if handleGetTunFailed() {
		t.Error("a config without TUN is reported as failed")
	}
}
