//go:build darwin

package systemconfiguration

import (
	"crypto/rand"
	"fmt"
	"net/netip"
	"runtime"
	"sync"
	"unsafe"

	"golang.org/x/sys/unix"
)

const (
	cfStringEncodingUTF8 = 0x08000100
	cfNumberSInt32Type   = 3
)

// DNSRegistration owns a temporary resolver in the system dynamic store.
type DNSRegistration struct {
	closeOnce sync.Once
	functions *frameworkFunctions
	session   uintptr
}

// RegisterDNS publishes a catch-all resolver without overwriting existing services.
// The key belongs to this session and is removed when it closes or the process
// exits, so no persistent DNS settings need to be backed up or restored.
func RegisterDNS(interfaceName string, servers []netip.Addr) (*DNSRegistration, error) {
	functions, err := loadFrameworkAPI()
	if err != nil {
		return nil, err
	}

	var serviceID [16]byte
	if _, err := rand.Read(serviceID[:]); err != nil {
		return nil, err
	}

	storeKey := fmt.Sprintf("State:/Network/Service/sing-tun-%x/DNS", serviceID)
	return functions.registerDNS(interfaceName, storeKey, servers)
}

func (d *DNSRegistration) Close() error {
	d.closeOnce.Do(func() {
		d.functions.cfRelease(d.session)
	})

	return nil
}

type frameworkFunctions struct {
	cfStringCreateWithCString func(uintptr, string, uint32) uintptr
	cfArrayCreate             func(uintptr, []uintptr, int, uintptr) uintptr
	cfDictionaryCreate        func(uintptr, []uintptr, []uintptr, int, uintptr, uintptr) uintptr
	cfNumberCreate            func(uintptr, int, *int32) uintptr
	cfRelease                 func(uintptr)

	cfTypeArrayCallbacks            uintptr
	cfTypeDictionaryKeyCallbacks    uintptr
	cfTypeDictionaryValueCallbacks  uintptr
	scDynamicStoreCreate            func(uintptr, uintptr, uintptr, uintptr) uintptr
	scDynamicStoreAddTemporaryValue func(uintptr, uintptr, uintptr) bool
	scError                         func() int32
	scErrorString                   func(int32) string
}

var (
	frameworkLoadOnce sync.Once
	frameworkAPI      frameworkFunctions
	frameworkLoadErr  error
)

func loadFrameworkAPI() (*frameworkFunctions, error) {
	frameworkLoadOnce.Do(func() {
		frameworkLoadErr = frameworkAPI.load()
	})

	return &frameworkAPI, frameworkLoadErr
}

func (f *frameworkFunctions) load() error {
	// Keep the frameworks loaded for the lifetime of the process: the bound
	// functions and CoreFoundation collection callbacks point into them.
	cf, err := dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
	if err != nil {
		return err
	}
	sc, err := dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration")
	if err != nil {
		return err
	}

	var (
		cfStringCreateWithCString       uintptr
		cfArrayCreate                   uintptr
		cfDictionaryCreate              uintptr
		cfNumberCreate                  uintptr
		cfRelease                       uintptr
		scDynamicStoreCreate            uintptr
		scDynamicStoreAddTemporaryValue uintptr
		scError                         uintptr
		scErrorString                   uintptr
	)
	for _, binding := range []struct {
		library uintptr
		name    string
		ptr     *uintptr
	}{
		{cf, "CFStringCreateWithCString", &cfStringCreateWithCString},
		{cf, "CFArrayCreate", &cfArrayCreate},
		{cf, "CFDictionaryCreate", &cfDictionaryCreate},
		{cf, "CFNumberCreate", &cfNumberCreate},
		{cf, "CFRelease", &cfRelease},
		{cf, "kCFTypeArrayCallBacks", &f.cfTypeArrayCallbacks},
		{cf, "kCFTypeDictionaryKeyCallBacks", &f.cfTypeDictionaryKeyCallbacks},
		{cf, "kCFTypeDictionaryValueCallBacks", &f.cfTypeDictionaryValueCallbacks},
		{sc, "SCDynamicStoreCreate", &scDynamicStoreCreate},
		{sc, "SCDynamicStoreAddTemporaryValue", &scDynamicStoreAddTemporaryValue},
		{sc, "SCError", &scError},
		{sc, "SCErrorString", &scErrorString},
	} {
		*binding.ptr, err = dlsym(binding.library, binding.name)
		if err != nil {
			return err
		}
	}

	f.cfStringCreateWithCString = func(allocator uintptr, value string, encoding uint32) uintptr {
		cString := append([]byte(value), 0)
		ref, _, _ := syscall_syscall(cfStringCreateWithCString, allocator, uintptr(unsafe.Pointer(&cString[0])), uintptr(encoding))
		return ref
	}
	f.cfArrayCreate = func(allocator uintptr, values []uintptr, count int, callbacks uintptr) uintptr {
		ref, _, _ := syscall_syscall6(cfArrayCreate, allocator, uintptr(unsafe.Pointer(unsafe.SliceData(values))), uintptr(count), callbacks, 0, 0)
		return ref
	}
	f.cfDictionaryCreate = func(allocator uintptr, keys []uintptr, values []uintptr, count int, keyCallbacks uintptr, valueCallbacks uintptr) uintptr {
		ref, _, _ := syscall_syscall6(cfDictionaryCreate, allocator, uintptr(unsafe.Pointer(unsafe.SliceData(keys))), uintptr(unsafe.Pointer(unsafe.SliceData(values))), uintptr(count), keyCallbacks, valueCallbacks)
		return ref
	}
	f.cfNumberCreate = func(allocator uintptr, numberType int, value *int32) uintptr {
		ref, _, _ := syscall_syscall(cfNumberCreate, allocator, uintptr(numberType), uintptr(unsafe.Pointer(value)))
		return ref
	}
	f.cfRelease = func(ref uintptr) {
		syscall_syscall(cfRelease, ref, 0, 0)
	}
	f.scDynamicStoreCreate = func(allocator, name, callout, context uintptr) uintptr {
		ref, _, _ := syscall_syscall6(scDynamicStoreCreate, allocator, name, callout, context, 0, 0)
		return ref
	}
	f.scDynamicStoreAddTemporaryValue = func(store, key, value uintptr) bool {
		ok, _, _ := syscall_syscall(scDynamicStoreAddTemporaryValue, store, key, value)
		// Boolean is an unsigned char; the upper bits of the register are undefined.
		return uint8(ok) != 0
	}
	f.scError = func() int32 {
		code, _, _ := syscall_syscall(scError, 0, 0, 0)
		return int32(code)
	}
	f.scErrorString = func(code int32) string {
		message, _, _ := syscall_syscall(scErrorString, uintptr(code), 0, 0)
		// message points to a static C string owned by SystemConfiguration.
		return unix.BytePtrToString(*(**byte)(unsafe.Pointer(&message)))
	}

	return nil
}

func (f *frameworkFunctions) createString(value string) uintptr {
	return f.cfStringCreateWithCString(0, value, cfStringEncodingUTF8)
}

func (f *frameworkFunctions) createStringArray(values []string) uintptr {
	refs := make([]uintptr, len(values))
	for i, value := range values {
		refs[i] = f.createString(value)
		defer f.cfRelease(refs[i])
	}

	return f.cfArrayCreate(0, refs, len(refs), f.cfTypeArrayCallbacks)
}

func (f *frameworkFunctions) createDNSDictionary(servers []netip.Addr) uintptr {
	addresses := make([]string, len(servers))
	for i, server := range servers {
		addresses[i] = server.String()
	}

	serverArray := f.createStringArray(addresses)
	defer f.cfRelease(serverArray)

	// An empty supplemental match domain is the catch-all, like resolved's ~.
	domains := f.createStringArray([]string{""})
	defer f.cfRelease(domains)

	// Prefer this resolver to the default service for otherwise unmatched names.
	order := int32(1)
	searchOrder := f.cfNumberCreate(0, cfNumberSInt32Type, &order)
	defer f.cfRelease(searchOrder)

	keys := []uintptr{
		f.createString("ServerAddresses"),
		f.createString("SupplementalMatchDomains"),
		f.createString("SupplementalMatchOrders"),
	}
	for _, key := range keys {
		defer f.cfRelease(key)
	}

	orders := f.cfArrayCreate(0, []uintptr{searchOrder}, 1, f.cfTypeArrayCallbacks)
	defer f.cfRelease(orders)

	values := []uintptr{serverArray, domains, orders}
	return f.cfDictionaryCreate(
		0,
		keys,
		values,
		len(keys),
		f.cfTypeDictionaryKeyCallbacks,
		f.cfTypeDictionaryValueCallbacks,
	)
}

func (f *frameworkFunctions) registerDNS(interfaceName, storeKey string, servers []netip.Addr) (*DNSRegistration, error) {
	// SCError is thread-local; read it on the same OS thread as the failed call.
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	label := f.createString("sing-tun " + interfaceName)
	defer f.cfRelease(label)

	session := f.scDynamicStoreCreate(0, label, 0, 0)
	if session == 0 {
		return nil, fmt.Errorf("SCDynamicStoreCreate: %s", f.scErrorString(f.scError()))
	}

	registration := &DNSRegistration{
		functions: f,
		session:   session,
	}

	keyRef := f.createString(storeKey)
	defer f.cfRelease(keyRef)

	dictionary := f.createDNSDictionary(servers)
	defer f.cfRelease(dictionary)

	if !f.scDynamicStoreAddTemporaryValue(session, keyRef, dictionary) {
		err := fmt.Errorf("SCDynamicStoreAddTemporaryValue: %s", f.scErrorString(f.scError()))
		registration.Close()
		return nil, err
	}

	return registration, nil
}
