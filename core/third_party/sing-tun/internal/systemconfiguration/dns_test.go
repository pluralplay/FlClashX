//go:build darwin

package systemconfiguration

import (
	"net/netip"
	"reflect"
	"strings"
	"testing"
	"unsafe"
)

func TestDNSDictionary(t *testing.T) {
	functions, err := loadFrameworkAPI()
	if err != nil {
		t.Fatal(err)
	}
	cf, err := dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
	if err != nil {
		t.Fatal(err)
	}
	lookup := func(name string) uintptr {
		symbol, err := dlsym(cf, name)
		if err != nil {
			t.Fatal(err)
		}
		return symbol
	}
	cfDictionaryGetValue := lookup("CFDictionaryGetValue")
	cfArrayGetCount := lookup("CFArrayGetCount")
	cfArrayGetValueAtIndex := lookup("CFArrayGetValueAtIndex")
	cfStringGetCString := lookup("CFStringGetCString")
	cfNumberGetValue := lookup("CFNumberGetValue")
	dictionaryGet := func(dict, key uintptr) uintptr {
		value, _, _ := syscall_syscall(cfDictionaryGetValue, dict, key, 0)
		return value
	}
	arrayCount := func(array uintptr) int {
		count, _, _ := syscall_syscall(cfArrayGetCount, array, 0, 0)
		return int(count)
	}
	arrayGet := func(array uintptr, index int) uintptr {
		value, _, _ := syscall_syscall(cfArrayGetValueAtIndex, array, uintptr(index), 0)
		return value
	}
	stringGet := func(ref uintptr, buffer []byte, size int, encoding uint32) bool {
		ok, _, _ := syscall_syscall6(cfStringGetCString, ref, uintptr(unsafe.Pointer(&buffer[0])), uintptr(size), uintptr(encoding), 0, 0)
		return uint8(ok) != 0
	}
	numberGet := func(ref uintptr, numberType int, value *int32) bool {
		ok, _, _ := syscall_syscall(cfNumberGetValue, ref, uintptr(numberType), uintptr(unsafe.Pointer(value)))
		return uint8(ok) != 0
	}
	for _, servers := range [][]netip.Addr{
		{netip.MustParseAddr("192.0.2.2")},
		{netip.MustParseAddr("2001:db8::2")},
		{netip.MustParseAddr("192.0.2.2"), netip.MustParseAddr("2001:db8::2")},
	} {
		dict := functions.createDNSDictionary(servers)
		get := func(key string) uintptr {
			ref := functions.createString(key)
			defer functions.cfRelease(ref)
			value := dictionaryGet(dict, ref)
			if value == 0 {
				t.Fatalf("missing key %s", key)
			}
			return value
		}
		readStrings := func(array uintptr) []string {
			values := make([]string, arrayCount(array))
			for i := range values {
				buffer := make([]byte, 128)
				if !stringGet(arrayGet(array, i), buffer, len(buffer), cfStringEncodingUTF8) {
					t.Fatal("CFStringGetCString failed")
				}
				values[i] = strings.TrimRight(string(buffer), "\x00")
			}
			return values
		}
		want := make([]string, len(servers))
		for i, server := range servers {
			want[i] = server.String()
		}
		if got := readStrings(get("ServerAddresses")); !reflect.DeepEqual(got, want) {
			t.Fatalf("servers = %v, want %v", got, want)
		}
		if got := readStrings(get("SupplementalMatchDomains")); !reflect.DeepEqual(got, []string{""}) {
			t.Fatalf("match domains = %v", got)
		}
		orders := get("SupplementalMatchOrders")
		var order int32
		if arrayCount(orders) != 1 || !numberGet(arrayGet(orders, 0), cfNumberSInt32Type, &order) || order != 1 {
			t.Fatalf("unexpected match order %d", order)
		}
		functions.cfRelease(dict)
	}
}

func TestDNSRegistrationLifecycle(t *testing.T) {
	loadedFunctions, err := loadFrameworkAPI()
	if err != nil {
		t.Fatal(err)
	}
	for _, stage := range []string{"create error", "add error", "success"} {
		t.Run(stage, func(t *testing.T) {
			functions := *loadedFunctions
			// Use real CoreFoundation values, but never publish functions resolver while
			// testing. Only the dynamic store boundary is replaced.
			session := functions.createString("test session")
			releases, adds := 0, 0
			functions.cfRelease = func(ref uintptr) {
				if ref == session {
					releases++
					return
				}
				loadedFunctions.cfRelease(ref)
			}
			defer loadedFunctions.cfRelease(session)
			functions.scDynamicStoreCreate = func(_, _, _, _ uintptr) uintptr {
				if stage == "create error" {
					return 0
				}
				return session
			}
			functions.scDynamicStoreAddTemporaryValue = func(store, key, value uintptr) bool {
				adds++
				if store != session || key == 0 || value == 0 {
					t.Fatal("invalid dynamic store arguments")
				}
				return stage == "success"
			}
			functions.scError = func() int32 {
				return 1003
			}
			dns, err := functions.registerDNS("utun123", "State:/Network/Service/test/DNS", []netip.Addr{netip.MustParseAddr("192.0.2.2")})
			switch stage {
			case "create error":
				if dns != nil || err == nil || adds != 0 || releases != 0 {
					t.Fatalf("unexpected create failure: dns=%v err=%v adds=%d releases=%d", dns, err, adds, releases)
				}
			case "add error":
				if dns != nil || err == nil || adds != 1 || releases != 1 {
					t.Fatalf("unexpected add failure: dns=%v err=%v adds=%d releases=%d", dns, err, adds, releases)
				}
			case "success":
				if err != nil || releases != 0 || adds != 1 {
					t.Fatalf("unexpected setup: err=%v adds=%d releases=%d", err, adds, releases)
				}
				dns.Close()
				dns.Close()
				if releases != 1 {
					t.Fatalf("session released %d times", releases)
				}
			}
		})
	}
}
