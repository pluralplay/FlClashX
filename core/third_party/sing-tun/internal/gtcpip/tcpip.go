// Copyright 2024 The gVisor Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package tcpip

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math"
	"math/bits"
	"net"
	"strconv"
	"strings"
	"time"
)

// Using the header package here would cause an import cycle.
const (
	ipv4AddressSize    = 4
	ipv4ProtocolNumber = 0x0800
	ipv6AddressSize    = 16
	ipv6ProtocolNumber = 0x86dd
)

const (
	// LinkAddressSize is the size of a MAC address.
	LinkAddressSize = 6
)

// Known IP address.
var (
	IPv4Zero = []byte{0, 0, 0, 0}
	IPv6Zero = []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
)

// Errors related to Subnet
var (
	errSubnetLengthMismatch = errors.New("subnet length of address and mask differ")
	errSubnetAddressMasked  = errors.New("subnet address has bits set outside the mask")
)

// TransportProtocolNumber is the number of a transport protocol.
type TransportProtocolNumber uint32

// NetworkProtocolNumber is the EtherType of a network protocol in an Ethernet
// frame.
//
// See: https://www.iana.org/assignments/ieee-802-numbers/ieee-802-numbers.xhtml
type NetworkProtocolNumber uint32

// MonotonicTime is a monotonic clock reading.
//
// +stateify savable
type MonotonicTime struct {
	nanoseconds int64
}

// String implements Stringer.
func (mt MonotonicTime) String() string {
	return strconv.FormatInt(mt.nanoseconds, 10)
}

// MonotonicTimeInfinite returns the monotonic timestamp as far away in the
// future as possible.
func MonotonicTimeInfinite() MonotonicTime {
	return MonotonicTime{nanoseconds: math.MaxInt64}
}

// Before reports whether the monotonic clock reading mt is before u.
func (mt MonotonicTime) Before(u MonotonicTime) bool {
	return mt.nanoseconds < u.nanoseconds
}

// After reports whether the monotonic clock reading mt is after u.
func (mt MonotonicTime) After(u MonotonicTime) bool {
	return mt.nanoseconds > u.nanoseconds
}

// Add returns the monotonic clock reading mt+d.
func (mt MonotonicTime) Add(d time.Duration) MonotonicTime {
	return MonotonicTime{
		nanoseconds: time.Unix(0, mt.nanoseconds).Add(d).Sub(time.Unix(0, 0)).Nanoseconds(),
	}
}

// Sub returns the duration mt-u. If the result exceeds the maximum (or minimum)
// value that can be stored in a Duration, the maximum (or minimum) duration
// will be returned. To compute t-d for a duration d, use t.Add(-d).
func (mt MonotonicTime) Sub(u MonotonicTime) time.Duration {
	return time.Unix(0, mt.nanoseconds).Sub(time.Unix(0, u.nanoseconds))
}

// Milliseconds returns the time in milliseconds.
func (mt MonotonicTime) Milliseconds() int64 {
	return mt.nanoseconds / 1e6
}

// A Clock provides the current time and schedules work for execution.
//
// Times returned by a Clock should always be used for application-visible
// time. Only monotonic times should be used for netstack internal timekeeping.
type Clock interface {
	// Now returns the current local time.
	Now() time.Time

	// NowMonotonic returns the current monotonic clock reading.
	NowMonotonic() MonotonicTime

	// AfterFunc waits for the duration to elapse and then calls f in its own
	// goroutine. It returns a Timer that can be used to cancel the call using
	// its Stop method.
	AfterFunc(d time.Duration, f func()) Timer
}

// Timer represents a single event. A Timer must be created with
// Clock.AfterFunc.
type Timer interface {
	// Stop prevents the Timer from firing. It returns true if the call stops the
	// timer, false if the timer has already expired or been stopped.
	//
	// If Stop returns false, then the timer has already expired and the function
	// f of Clock.AfterFunc(d, f) has been started in its own goroutine; Stop
	// does not wait for f to complete before returning. If the caller needs to
	// know whether f is completed, it must coordinate with f explicitly.
	Stop() bool

	// Reset changes the timer to expire after duration d.
	//
	// Reset should be invoked only on stopped or expired timers. If the timer is
	// known to have expired, Reset can be used directly. Otherwise, the caller
	// must coordinate with the function f of Clock.AfterFunc(d, f).
	Reset(d time.Duration)
}

// Address is a byte slice cast as a string that represents the address of a
// network node. Or, in the case of unix endpoints, it may represent a path.
//
// +stateify savable
type Address struct {
	addr   [16]byte
	length int
}

// AddrFrom4 converts addr to an Address.
func AddrFrom4(addr [4]byte) Address {
	ret := Address{
		length: 4,
	}
	// It's guaranteed that copy will return 4.
	copy(ret.addr[:], addr[:])
	return ret
}

// AddrFrom4Slice converts addr to an Address. It panics if len(addr) != 4.
func AddrFrom4Slice(addr []byte) Address {
	if len(addr) != 4 {
		panic(fmt.Sprintf("bad address length for address %v", addr))
	}
	ret := Address{
		length: 4,
	}
	// It's guaranteed that copy will return 4.
	copy(ret.addr[:], addr)
	return ret
}

// AddrFrom16 converts addr to an Address.
func AddrFrom16(addr [16]byte) Address {
	ret := Address{
		length: 16,
	}
	// It's guaranteed that copy will return 16.
	copy(ret.addr[:], addr[:])
	return ret
}

// AddrFrom16Slice converts addr to an Address. It panics if len(addr) != 16.
func AddrFrom16Slice(addr []byte) Address {
	if len(addr) != 16 {
		panic(fmt.Sprintf("bad address length for address %v", addr))
	}
	ret := Address{
		length: 16,
	}
	// It's guaranteed that copy will return 16.
	copy(ret.addr[:], addr)
	return ret
}

// AddrFromSlice converts addr to an Address. It returns the Address zero value
// if len(addr) != 4 or 16.
func AddrFromSlice(addr []byte) Address {
	switch len(addr) {
	case ipv4AddressSize:
		return AddrFrom4Slice(addr)
	case ipv6AddressSize:
		return AddrFrom16Slice(addr)
	}
	return Address{}
}

// As4 returns a as a 4 byte array. It panics if the address length is not 4.
func (a Address) As4() [4]byte {
	if a.Len() != 4 {
		panic(fmt.Sprintf("bad address length for address %v", a.addr))
	}
	return [4]byte(a.addr[:4])
}

// As16 returns a as a 16 byte array. It panics if the address length is not 16.
func (a Address) As16() [16]byte {
	if a.Len() != 16 {
		panic(fmt.Sprintf("bad address length for address %v", a.addr))
	}
	return [16]byte(a.addr[:16])
}

// AsSlice returns a as a byte slice. Callers should be careful as it can
// return a window into existing memory.
//
// +checkescape
func (a *Address) AsSlice() []byte {
	return a.addr[:a.length]
}

// BitLen returns the length in bits of a.
func (a Address) BitLen() int {
	return a.Len() * 8
}

// Len returns the length in bytes of a.
func (a Address) Len() int {
	return a.length
}

// WithPrefix returns the address with a prefix that represents a point subnet.
func (a Address) WithPrefix() AddressWithPrefix {
	return AddressWithPrefix{
		Address:   a,
		PrefixLen: a.BitLen(),
	}
}

// Unspecified returns true if the address is unspecified.
func (a Address) Unspecified() bool {
	for _, b := range a.addr {
		if b != 0 {
			return false
		}
	}
	return true
}

// Equal returns whether a and other are equal. It exists for use by the cmp
// library.
func (a Address) Equal(other Address) bool {
	return a == other
}

// MatchingPrefix returns the matching prefix length in bits.
//
// Panics if b and a have different lengths.
func (a Address) MatchingPrefix(b Address) uint8 {
	const bitsInAByte = 8

	if a.Len() != b.Len() {
		panic(fmt.Sprintf("addresses %s and %s do not have the same length", a, b))
	}

	var prefix uint8
	for i := 0; i < a.length; i++ {
		aByte := a.addr[i]
		bByte := b.addr[i]

		if aByte == bByte {
			prefix += bitsInAByte
			continue
		}

		// Count the remaining matching bits in the byte from MSbit to LSBbit.
		mask := uint8(1) << (bitsInAByte - 1)
		for {
			if aByte&mask == bByte&mask {
				prefix++
				mask >>= 1
				continue
			}

			break
		}

		break
	}

	return prefix
}

// AddressMask is a bitmask for an address.
//
// +stateify savable
type AddressMask struct {
	mask   [16]byte
	length int
}

// MaskFrom returns a Mask based on str.
//
// MaskFrom may allocate, and so should not be in hot paths.
func MaskFrom(str string) AddressMask {
	mask := AddressMask{length: len(str)}
	copy(mask.mask[:], str)
	return mask
}

// MaskFromBytes returns a Mask based on bs.
func MaskFromBytes(bs []byte) AddressMask {
	mask := AddressMask{length: len(bs)}
	copy(mask.mask[:], bs)
	return mask
}

// String implements Stringer.
func (m AddressMask) String() string {
	return fmt.Sprintf("%x", m.mask)
}

// AsSlice returns a as a byte slice. Callers should be careful as it can
// return a window into existing memory.
func (m *AddressMask) AsSlice() []byte {
	return []byte(m.mask[:m.length])
}

// BitLen returns the length of the mask in bits.
func (m AddressMask) BitLen() int {
	return m.length * 8
}

// Len returns the length of the mask in bytes.
func (m AddressMask) Len() int {
	return m.length
}

// Prefix returns the number of bits before the first host bit.
func (m AddressMask) Prefix() int {
	p := 0
	for _, b := range m.mask[:m.length] {
		p += bits.LeadingZeros8(^b)
	}
	return p
}

// Equal returns whether m and other are equal. It exists for use by the cmp
// library.
func (m AddressMask) Equal(other AddressMask) bool {
	return m == other
}

// Subnet is a subnet defined by its address and mask.
//
// +stateify savable
type Subnet struct {
	address Address
	mask    AddressMask
}

// NewSubnet creates a new Subnet, checking that the address and mask are the same length.
func NewSubnet(a Address, m AddressMask) (Subnet, error) {
	if a.Len() != m.Len() {
		return Subnet{}, errSubnetLengthMismatch
	}
	for i := 0; i < a.Len(); i++ {
		if a.addr[i]&^m.mask[i] != 0 {
			return Subnet{}, errSubnetAddressMasked
		}
	}
	return Subnet{a, m}, nil
}

// String implements Stringer.
func (s Subnet) String() string {
	return fmt.Sprintf("%s/%d", s.ID(), s.Prefix())
}

// Contains returns true iff the address is of the same length and matches the
// subnet address and mask.
func (s *Subnet) Contains(a Address) bool {
	if a.Len() != s.address.Len() {
		return false
	}
	for i := 0; i < a.Len(); i++ {
		if a.addr[i]&s.mask.mask[i] != s.address.addr[i] {
			return false
		}
	}
	return true
}

// ID returns the subnet ID.
func (s *Subnet) ID() Address {
	return s.address
}

// Bits returns the number of ones (network bits) and zeros (host bits) in the
// subnet mask.
func (s *Subnet) Bits() (ones int, zeros int) {
	ones = s.mask.Prefix()
	return ones, s.mask.BitLen() - ones
}

// Prefix returns the number of bits before the first host bit.
func (s *Subnet) Prefix() int {
	return s.mask.Prefix()
}

// Mask returns the subnet mask.
func (s *Subnet) Mask() AddressMask {
	return s.mask
}

// Broadcast returns the subnet's broadcast address.
func (s *Subnet) Broadcast() Address {
	addrCopy := s.address
	for i := 0; i < addrCopy.Len(); i++ {
		addrCopy.addr[i] |= ^s.mask.mask[i]
	}
	return addrCopy
}

// IsBroadcast returns true if the address is considered a broadcast address.
func (s *Subnet) IsBroadcast(address Address) bool {
	// Only IPv4 supports the notion of a broadcast address.
	if address.Len() != ipv4AddressSize {
		return false
	}

	// Normally, we would just compare address with the subnet's broadcast
	// address but there is an exception where a simple comparison is not
	// correct. This exception is for /31 and /32 IPv4 subnets where all
	// addresses are considered valid host addresses.
	//
	// For /31 subnets, the case is easy. RFC 3021 Section 2.1 states that
	// both addresses in a /31 subnet "MUST be interpreted as host addresses."
	//
	// For /32, the case is a bit more vague. RFC 3021 makes no mention of /32
	// subnets. However, the same reasoning applies - if an exception is not
	// made, then there do not exist any host addresses in a /32 subnet. RFC
	// 4632 Section 3.1 also vaguely implies this interpretation by referring
	// to addresses in /32 subnets as "host routes."
	return s.Prefix() <= 30 && s.Broadcast() == address
}

// Equal returns true if this Subnet is equal to the given Subnet.
func (s Subnet) Equal(o Subnet) bool {
	// If this changes, update Route.Equal accordingly.
	return s == o
}

// LinkAddress is a byte slice cast as a string that represents a link address.
// It is typically a 6-byte MAC address.
type LinkAddress string

// String implements the fmt.Stringer interface.
func (a LinkAddress) String() string {
	switch len(a) {
	case 6:
		return fmt.Sprintf("%02x:%02x:%02x:%02x:%02x:%02x", a[0], a[1], a[2], a[3], a[4], a[5])
	default:
		return fmt.Sprintf("%x", []byte(a))
	}
}

// ParseMACAddress parses an IEEE 802 address.
//
// It must be in the format aa:bb:cc:dd:ee:ff or aa-bb-cc-dd-ee-ff.
func ParseMACAddress(s string) (LinkAddress, error) {
	parts := strings.FieldsFunc(s, func(c rune) bool {
		return c == ':' || c == '-'
	})
	if len(parts) != LinkAddressSize {
		return "", fmt.Errorf("inconsistent parts: %s", s)
	}
	addr := make([]byte, 0, len(parts))
	for _, part := range parts {
		u, err := strconv.ParseUint(part, 16, 8)
		if err != nil {
			return "", fmt.Errorf("invalid hex digits: %s", s)
		}
		addr = append(addr, byte(u))
	}
	return LinkAddress(addr), nil
}

// GetRandMacAddr returns a mac address that can be used for local virtual devices.
func GetRandMacAddr() LinkAddress {
	mac := make(net.HardwareAddr, LinkAddressSize)
	rand.Read(mac) // Fill with random data.
	mac[0] &^= 0x1 // Clear multicast bit.
	mac[0] |= 0x2  // Set local assignment bit (IEEE802).
	return LinkAddress(mac)
}

// AddressWithPrefix is an address with its subnet prefix length.
//
// +stateify savable
type AddressWithPrefix struct {
	// Address is a network address.
	Address Address

	// PrefixLen is the subnet prefix length.
	PrefixLen int
}

// String implements the fmt.Stringer interface.
func (a AddressWithPrefix) String() string {
	return fmt.Sprintf("%s/%d", a.Address, a.PrefixLen)
}

// Subnet converts the address and prefix into a Subnet value and returns it.
func (a AddressWithPrefix) Subnet() Subnet {
	addrLen := a.Address.length
	if a.PrefixLen <= 0 {
		return Subnet{
			address: Address{length: addrLen},
			mask:    AddressMask{length: addrLen},
		}
	}
	if a.PrefixLen >= addrLen*8 {
		sub := Subnet{
			address: a.Address,
			mask:    AddressMask{length: addrLen},
		}
		for i := 0; i < addrLen; i++ {
			sub.mask.mask[i] = 0xff
		}
		return sub
	}

	sa := Address{length: addrLen}
	sm := AddressMask{length: addrLen}
	n := uint(a.PrefixLen)
	for i := 0; i < addrLen; i++ {
		if n >= 8 {
			sa.addr[i] = a.Address.addr[i]
			sm.mask[i] = 0xff
			n -= 8
			continue
		}
		sm.mask[i] = ^byte(0xff >> n)
		sa.addr[i] = a.Address.addr[i] & sm.mask[i]
		n = 0
	}

	// For extra caution, call NewSubnet rather than directly creating the Subnet
	// value. If that fails it indicates a serious bug in this code, so panic is
	// in order.
	s, err := NewSubnet(sa, sm)
	if err != nil {
		panic("invalid subnet: " + err.Error())
	}
	return s
}
