package core

import (
	"io"
	"sync"
	"sync/atomic"
)

type TunCallbacks interface {
	Protect(fd int) bool
	ResolveUid(protocol int, source, target string) int
	ResolvePackage(uid int) string
}

type TunHandler struct {
	listener  io.Closer
	callbacks TunCallbacks

	mu sync.RWMutex
}

var (
	tunLock          sync.Mutex
	tunHandler       *TunHandler
	activeTunHandler atomic.Pointer[TunHandler]
)

// Android has the routes up before it hands over the descriptor, so the new
// handler protects sockets from here on, through the wait for configMu too.
func startTunLocked(callbacks TunCallbacks, open func() io.Closer) bool {
	previous := tunHandler
	tunHandler = &TunHandler{callbacks: callbacks}
	activeTunHandler.Store(tunHandler)
	if previous != nil {
		previous.close()
	}
	if tunHandler.start(open) {
		return true
	}
	tunHandler = nil
	return false
}

func (th *TunHandler) start(open func() io.Closer) bool {
	configMu.Lock()
	defer configMu.Unlock()

	// Outside th.mu: a socket opened inside reaches handleProtect on this goroutine.
	listener := open()

	th.mu.Lock()
	defer th.mu.Unlock()
	if listener != nil {
		th.listener = listener
		return true
	}
	th.clear()
	return false
}

func (th *TunHandler) close() {
	th.mu.Lock()
	defer th.mu.Unlock()
	th.clear()
}

func (th *TunHandler) clear() {
	th.removeHook()
	if th.listener != nil {
		_ = th.listener.Close()
	}
	th.callbacks = nil
	th.listener = nil
}

// A hook that loaded th before a restart cleared it hands fd on to the
// handler that replaced it, so a dial in flight across the swap is protected.
func protectFrom(th *TunHandler, fd int) {
	for th != nil && !th.handleProtect(fd) {
		next := activeTunHandler.Load()
		if next == th {
			return
		}
		th = next
	}
}

func (th *TunHandler) handleProtect(fd int) bool {
	th.mu.RLock()
	defer th.mu.RUnlock()

	if th.callbacks == nil {
		return false
	}
	th.callbacks.Protect(fd)
	return true
}

// Swap the handler, never the hook: mihomo nil-checks DefaultSocketHook once and
// calls it later, so a hook cleared mid-dial calls a nil func value.
func (th *TunHandler) removeHook() {
	activeTunHandler.CompareAndSwap(th, nil)
}

func handleStopTun() {
	tunLock.Lock()
	defer tunLock.Unlock()
	stopTunLocked()
}

func stopTunLocked() {
	if tunHandler == nil {
		return
	}
	tunHandler.close()
	tunHandler = nil
}
