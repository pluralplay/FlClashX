package core

import (
	"io"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type protectRecorder struct {
	mu  sync.Mutex
	fds []int
}

func (r *protectRecorder) Protect(fd int) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.fds = append(r.fds, fd)
	return true
}

func (r *protectRecorder) ResolveUid(int, string, string) int { return -1 }
func (r *protectRecorder) ResolvePackage(int) string          { return "" }

func (r *protectRecorder) protected() []int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.fds)
}

type fakeTunListener struct {
	closed  atomic.Bool
	onClose func()
}

func (l *fakeTunListener) Close() error {
	if l.onClose != nil {
		l.onClose()
	}
	l.closed.Store(true)
	return nil
}

// The path dialer.DefaultSocketHook takes for every socket mihomo opens.
func openSocket(fd int) {
	if th := activeTunHandler.Load(); th != nil {
		protectFrom(th, fd)
	}
}

func startTestTun(t *testing.T, callbacks TunCallbacks, open func() io.Closer) bool {
	t.Helper()
	t.Cleanup(handleStopTun)
	started := make(chan bool, 1)
	go func() {
		tunLock.Lock()
		defer tunLock.Unlock()
		started <- startTunLocked(callbacks, open)
	}()
	select {
	case ok := <-started:
		return ok
	case <-time.After(5 * time.Second):
		t.Fatal("the TUN start never returned")
		return false
	}
}

func TestASocketOpenedWhileTheTunStartsIsProtected(t *testing.T) {
	callbacks := &protectRecorder{}
	started := startTestTun(t, callbacks, func() io.Closer {
		openSocket(7)
		return &fakeTunListener{}
	})
	if !started {
		t.Fatal("the start failed")
	}
	openSocket(8)
	if got := callbacks.protected(); !slices.Equal(got, []int{7, 8}) {
		t.Errorf("protected %v, want the socket opened inside the start and the one after it", got)
	}
}

func TestASocketOpenedWhileTheStartWaitsForTheConfigIsProtected(t *testing.T) {
	callbacks := &protectRecorder{}
	configMu.Lock()
	go func() {
		defer configMu.Unlock()
		deadline := time.Now().Add(4 * time.Second)
		for activeTunHandler.Load() == nil && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
		openSocket(9)
	}()
	if !startTestTun(t, callbacks, func() io.Closer { return &fakeTunListener{} }) {
		t.Fatal("the start failed")
	}
	if got := callbacks.protected(); !slices.Equal(got, []int{9}) {
		t.Errorf("protected %v, want the socket opened while a config apply held the start", got)
	}
}

func TestARestartedTunHandsProtectionOverWithoutAGap(t *testing.T) {
	first, second := &protectRecorder{}, &protectRecorder{}
	firstListener := &fakeTunListener{onClose: func() { openSocket(4) }}
	startTestTun(t, first, func() io.Closer { return firstListener })

	started := startTestTun(t, second, func() io.Closer {
		if !firstListener.closed.Load() {
			t.Error("the new TUN opened before the previous one closed")
		}
		openSocket(5)
		return &fakeTunListener{}
	})
	if !started {
		t.Fatal("the restart failed")
	}
	if got := first.protected(); len(got) != 0 {
		t.Errorf("the previous callbacks protected %v, want none once they were replaced", got)
	}
	if got := second.protected(); !slices.Equal(got, []int{4, 5}) {
		t.Errorf("protected %v, want the sockets opened while the previous TUN closed and the new one opened", got)
	}
}

func TestADialInFlightAcrossARestartIsProtectedByTheNewTun(t *testing.T) {
	first, second := &protectRecorder{}, &protectRecorder{}
	startTestTun(t, first, func() io.Closer { return &fakeTunListener{} })
	loaded := activeTunHandler.Load()
	startTestTun(t, second, func() io.Closer { return &fakeTunListener{} })

	protectFrom(loaded, 7)

	if got := first.protected(); len(got) != 0 {
		t.Errorf("the replaced callbacks protected %v, want none", got)
	}
	if got := second.protected(); !slices.Equal(got, []int{7}) {
		t.Errorf("protected %v, want the socket the stale hook still held", got)
	}
}

func TestAStoppedTunStopsProtecting(t *testing.T) {
	callbacks := &protectRecorder{}
	listener := &fakeTunListener{}
	startTestTun(t, callbacks, func() io.Closer { return listener })
	handler := activeTunHandler.Load()

	handleStopTun()
	if !listener.closed.Load() || activeTunHandler.Load() != nil {
		t.Fatalf("closed = %v, active = %v, want the listener closed and no handler", listener.closed.Load(), activeTunHandler.Load())
	}
	openSocket(3)
	handler.handleProtect(3)
	if got := callbacks.protected(); len(got) != 0 {
		t.Errorf("protected %v after the stop, want none", got)
	}
}

func TestAFailedTunStartStopsProtecting(t *testing.T) {
	callbacks := &protectRecorder{}
	if startTestTun(t, callbacks, func() io.Closer { return nil }) {
		t.Fatal("a start without a listener reported success")
	}
	if activeTunHandler.Load() != nil || tunHandler != nil {
		t.Fatal("a failed start left a handler behind")
	}
	openSocket(6)
	if got := callbacks.protected(); len(got) != 0 {
		t.Errorf("protected %v after the failed start, want none", got)
	}
}
