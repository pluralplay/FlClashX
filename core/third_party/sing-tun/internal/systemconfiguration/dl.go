//go:build darwin

package systemconfiguration

import (
	"fmt"
	"syscall"
	"unsafe"
)

const (
	rtldNow   = 0x2
	rtldLocal = 0x4
)

// dlopen and dlsym come from libSystem, which every darwin binary links, so this
// works with both the internal and the external linker without cgo.

//go:cgo_import_dynamic libc_dlopen dlopen "/usr/lib/libSystem.B.dylib"
//go:cgo_import_dynamic libc_dlsym dlsym "/usr/lib/libSystem.B.dylib"

var (
	libc_dlopen_trampoline_addr uintptr
	libc_dlsym_trampoline_addr  uintptr
)

func dlopen(path string) (uintptr, error) {
	pathPtr, err := syscall.BytePtrFromString(path)
	if err != nil {
		return 0, err
	}
	handle, _, _ := syscall_syscall(libc_dlopen_trampoline_addr, uintptr(unsafe.Pointer(pathPtr)), rtldNow|rtldLocal, 0)
	if handle == 0 {
		return 0, fmt.Errorf("dlopen %s failed", path)
	}
	return handle, nil
}

func dlsym(handle uintptr, name string) (uintptr, error) {
	namePtr, err := syscall.BytePtrFromString(name)
	if err != nil {
		return 0, err
	}
	symbol, _, _ := syscall_syscall(libc_dlsym_trampoline_addr, handle, uintptr(unsafe.Pointer(namePtr)), 0)
	if symbol == 0 {
		return 0, fmt.Errorf("dlsym %s: symbol not found", name)
	}
	return symbol, nil
}

// Implemented in the runtime package (runtime/sys_darwin.go), see
// golang.org/x/sys/unix/syscall_darwin_libSystem.go.

//go:linkname syscall_syscall syscall.syscall
func syscall_syscall(fn, a1, a2, a3 uintptr) (r1, r2 uintptr, err syscall.Errno)

//go:linkname syscall_syscall6 syscall.syscall6
func syscall_syscall6(fn, a1, a2, a3, a4, a5, a6 uintptr) (r1, r2 uintptr, err syscall.Errno)
