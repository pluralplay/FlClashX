// Copyright 2020 The gVisor Authors.
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

package header

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"

	"github.com/metacubex/sing-tun/internal/gtcpip"
	"github.com/metacubex/sing/common"
)

// IPv6ExtensionHeaderIdentifier is an IPv6 extension header identifier.
type IPv6ExtensionHeaderIdentifier uint8

const (
	// IPv6HopByHopOptionsExtHdrIdentifier is the header identifier of a Hop by
	// Hop Options extension header, as per RFC 8200 section 4.3.
	IPv6HopByHopOptionsExtHdrIdentifier IPv6ExtensionHeaderIdentifier = 0

	// IPv6RoutingExtHdrIdentifier is the header identifier of a Routing extension
	// header, as per RFC 8200 section 4.4.
	IPv6RoutingExtHdrIdentifier IPv6ExtensionHeaderIdentifier = 43

	// IPv6FragmentExtHdrIdentifier is the header identifier of a Fragment
	// extension header, as per RFC 8200 section 4.5.
	IPv6FragmentExtHdrIdentifier IPv6ExtensionHeaderIdentifier = 44

	// IPv6DestinationOptionsExtHdrIdentifier is the header identifier of a
	// Destination Options extension header, as per RFC 8200 section 4.6.
	IPv6DestinationOptionsExtHdrIdentifier IPv6ExtensionHeaderIdentifier = 60

	// IPv6NoNextHeaderIdentifier is the header identifier used to signify the end
	// of an IPv6 payload, as per RFC 8200 section 4.7.
	IPv6NoNextHeaderIdentifier IPv6ExtensionHeaderIdentifier = 59

	// IPv6UnknownExtHdrIdentifier is reserved by IANA.
	// https://www.iana.org/assignments/ipv6-parameters/ipv6-parameters.xhtml#extension-header
	// "254	Use for experimentation and testing	[RFC3692][RFC4727]"
	IPv6UnknownExtHdrIdentifier IPv6ExtensionHeaderIdentifier = 254
)

const (
	// ipv6UnknownExtHdrOptionActionMask is the mask of the action to take when
	// a node encounters an unrecognized option.
	ipv6UnknownExtHdrOptionActionMask = 192

	// ipv6UnknownExtHdrOptionActionShift is the least significant bits to discard
	// from the action value for an unrecognized option identifier.
	ipv6UnknownExtHdrOptionActionShift = 6

	// ipv6RoutingExtHdrSegmentsLeftIdx is the index to the Segments Left field
	// within an IPv6RoutingExtHdr.
	ipv6RoutingExtHdrSegmentsLeftIdx = 1

	// IPv6FragmentExtHdrLength is the length of an IPv6 extension header, in
	// bytes.
	IPv6FragmentExtHdrLength = 8

	// ipv6FragmentExtHdrFragmentOffsetOffset is the offset to the start of the
	// Fragment Offset field within an IPv6FragmentExtHdr.
	ipv6FragmentExtHdrFragmentOffsetOffset = 0

	// ipv6FragmentExtHdrFragmentOffsetShift is the bit offset of the Fragment
	// Offset field within an IPv6FragmentExtHdr.
	ipv6FragmentExtHdrFragmentOffsetShift = 3

	// ipv6FragmentExtHdrFlagsIdx is the index to the flags field within an
	// IPv6FragmentExtHdr.
	ipv6FragmentExtHdrFlagsIdx = 1

	// ipv6FragmentExtHdrMFlagMask is the mask of the More (M) flag within the
	// flags field of an IPv6FragmentExtHdr.
	ipv6FragmentExtHdrMFlagMask = 1

	// ipv6FragmentExtHdrIdentificationOffset is the offset to the Identification
	// field within an IPv6FragmentExtHdr.
	ipv6FragmentExtHdrIdentificationOffset = 2

	// ipv6ExtHdrLenBytesPerUnit is the unit size of an extension header's length
	// field. That is, given a Length field of 2, the extension header expects
	// 16 bytes following the first 8 bytes (see ipv6ExtHdrLenBytesExcluded for
	// details about the first 8 bytes' exclusion from the Length field).
	ipv6ExtHdrLenBytesPerUnit = 8

	// ipv6ExtHdrLenBytesExcluded is the number of bytes excluded from an
	// extension header's Length field following the Length field.
	//
	// The Length field excludes the first 8 bytes, but the Next Header and Length
	// field take up the first 2 of the 8 bytes so we expect (at minimum) 6 bytes
	// after the Length field.
	//
	// This ensures that every extension header is at least 8 bytes.
	ipv6ExtHdrLenBytesExcluded = 6

	// IPv6FragmentExtHdrFragmentOffsetBytesPerUnit is the unit size of a Fragment
	// extension header's Fragment Offset field. That is, given a Fragment Offset
	// of 2, the extension header is indicating that the fragment's payload
	// starts at the 16th byte in the reassembled packet.
	IPv6FragmentExtHdrFragmentOffsetBytesPerUnit = 8
)

// padIPv6OptionsLength returns the total length for IPv6 options of length l
// considering the 8-octet alignment as stated in RFC 8200 Section 4.2.
func padIPv6OptionsLength(length int) int {
	return (length + ipv6ExtHdrLenBytesPerUnit - 1) & ^(ipv6ExtHdrLenBytesPerUnit - 1)
}

// padIPv6Option fills b with the appropriate padding options depending on its
// length.
func padIPv6Option(b []byte) {
	switch len(b) {
	case 0: // No padding needed.
	case 1: // Pad with Pad1.
		b[ipv6ExtHdrOptionTypeOffset] = uint8(ipv6Pad1ExtHdrOptionIdentifier)
	default: // Pad with PadN.
		s := b[ipv6ExtHdrOptionPayloadOffset:]
		common.ClearArray(s)
		b[ipv6ExtHdrOptionTypeOffset] = uint8(ipv6PadNExtHdrOptionIdentifier)
		b[ipv6ExtHdrOptionLengthOffset] = uint8(len(s))
	}
}

// ipv6OptionsAlignmentPadding returns the number of padding bytes needed to
// serialize an option at headerOffset with alignment requirements
// [align]n + alignOffset.
func ipv6OptionsAlignmentPadding(headerOffset int, align int, alignOffset int) int {
	padLen := headerOffset - alignOffset
	return ((padLen + align - 1) & ^(align - 1)) - padLen
}

// IPv6OptionUnknownAction is the action that must be taken if the processing
// IPv6 node does not recognize the option, as outlined in RFC 8200 section 4.2.
type IPv6OptionUnknownAction int

const (
	// IPv6OptionUnknownActionSkip indicates that the unrecognized option must
	// be skipped and the node should continue processing the header.
	IPv6OptionUnknownActionSkip IPv6OptionUnknownAction = 0

	// IPv6OptionUnknownActionDiscard indicates that the packet must be silently
	// discarded.
	IPv6OptionUnknownActionDiscard IPv6OptionUnknownAction = 1

	// IPv6OptionUnknownActionDiscardSendICMP indicates that the packet must be
	// discarded and the node must send an ICMP Parameter Problem, Code 2, message
	// to the packet's source, regardless of whether or not the packet's
	// Destination was a multicast address.
	IPv6OptionUnknownActionDiscardSendICMP IPv6OptionUnknownAction = 2

	// IPv6OptionUnknownActionDiscardSendICMPNoMulticastDest indicates that the
	// packet must be discarded and the node must send an ICMP Parameter Problem,
	// Code 2, message to the packet's source only if the packet's Destination was
	// not a multicast address.
	IPv6OptionUnknownActionDiscardSendICMPNoMulticastDest IPv6OptionUnknownAction = 3
)

// IPv6ExtHdrOption is implemented by the various IPv6 extension header options.
type IPv6ExtHdrOption interface {
	// UnknownAction returns the action to take in response to an unrecognized
	// option.
	UnknownAction() IPv6OptionUnknownAction

	// isIPv6ExtHdrOption is used to "lock" this interface so it is not
	// implemented by other packages.
	isIPv6ExtHdrOption()
}

// IPv6ExtHdrOptionIdentifier is an IPv6 extension header option identifier.
type IPv6ExtHdrOptionIdentifier uint8

const (
	// ipv6Pad1ExtHdrOptionIdentifier is the identifier for a padding option that
	// provides 1 byte padding, as outlined in RFC 8200 section 4.2.
	ipv6Pad1ExtHdrOptionIdentifier IPv6ExtHdrOptionIdentifier = 0

	// ipv6PadNExtHdrOptionIdentifier is the identifier for a padding option that
	// provides variable length byte padding, as outlined in RFC 8200 section 4.2.
	ipv6PadNExtHdrOptionIdentifier IPv6ExtHdrOptionIdentifier = 1

	// ipv6RouterAlertHopByHopOptionIdentifier is the identifier for the Router
	// Alert Hop by Hop option as defined in RFC 2711 section 2.1.
	ipv6RouterAlertHopByHopOptionIdentifier IPv6ExtHdrOptionIdentifier = 5

	// ipv6ExtHdrOptionTypeOffset is the option type offset in an extension header
	// option as defined in RFC 8200 section 4.2.
	ipv6ExtHdrOptionTypeOffset = 0

	// ipv6ExtHdrOptionLengthOffset is the option length offset in an extension
	// header option as defined in RFC 8200 section 4.2.
	ipv6ExtHdrOptionLengthOffset = 1

	// ipv6ExtHdrOptionPayloadOffset is the option payload offset in an extension
	// header option as defined in RFC 8200 section 4.2.
	ipv6ExtHdrOptionPayloadOffset = 2
)

// ipv6UnknownActionFromIdentifier maps an extension header option's
// identifier's high  bits to the action to take when the identifier is unknown.
func ipv6UnknownActionFromIdentifier(id IPv6ExtHdrOptionIdentifier) IPv6OptionUnknownAction {
	return IPv6OptionUnknownAction((id & ipv6UnknownExtHdrOptionActionMask) >> ipv6UnknownExtHdrOptionActionShift)
}

// ErrMalformedIPv6ExtHdrOption indicates that an IPv6 extension header option
// is malformed.
var ErrMalformedIPv6ExtHdrOption = errors.New("malformed IPv6 extension header option")

// IPv6FragmentExtHdr is a buffer holding the Fragment extension header specific
// data as outlined in RFC 8200 section 4.5.
//
// Note, the buffer does not include the Next Header and Reserved fields.
type IPv6FragmentExtHdr [6]byte

// isIPv6PayloadHeader implements IPv6PayloadHeader.isIPv6PayloadHeader.
func (IPv6FragmentExtHdr) isIPv6PayloadHeader() {}

// Release implements IPv6PayloadHeader.Release.
func (IPv6FragmentExtHdr) Release() {}

// FragmentOffset returns the Fragment Offset field.
//
// This value indicates where the buffer following the Fragment extension header
// starts in the target (reassembled) packet.
func (b IPv6FragmentExtHdr) FragmentOffset() uint16 {
	return binary.BigEndian.Uint16(b[ipv6FragmentExtHdrFragmentOffsetOffset:]) >> ipv6FragmentExtHdrFragmentOffsetShift
}

// More returns the More (M) flag.
//
// This indicates whether any fragments are expected to succeed b.
func (b IPv6FragmentExtHdr) More() bool {
	return b[ipv6FragmentExtHdrFlagsIdx]&ipv6FragmentExtHdrMFlagMask != 0
}

// ID returns the Identification field.
//
// This value is used to uniquely identify the packet, between a
// source and destination.
func (b IPv6FragmentExtHdr) ID() uint32 {
	return binary.BigEndian.Uint32(b[ipv6FragmentExtHdrIdentificationOffset:])
}

// IsAtomic returns whether the fragment header indicates an atomic fragment. An
// atomic fragment is a fragment that contains all the data required to
// reassemble a full packet.
func (b IPv6FragmentExtHdr) IsAtomic() bool {
	return !b.More() && b.FragmentOffset() == 0
}

// IPv6SerializableExtHdr provides serialization for IPv6 extension
// headers.
type IPv6SerializableExtHdr interface {
	// identifier returns the assigned IPv6 header identifier for this extension
	// header.
	identifier() IPv6ExtensionHeaderIdentifier

	// length returns the total serialized length in bytes of this extension
	// header, including the common next header and length fields.
	length() int

	// serializeInto serializes the receiver into the provided byte
	// buffer and with the provided nextHeader value.
	//
	// Note, the caller MUST provide a byte buffer with size of at least
	// length. Implementers of this function may assume that the byte buffer
	// is of sufficient size. serializeInto MAY panic if the provided byte
	// buffer is not of sufficient size.
	//
	// serializeInto returns the number of bytes that was used to serialize the
	// receiver. Implementers must only use the number of bytes required to
	// serialize the receiver. Callers MAY provide a larger buffer than required
	// to serialize into.
	serializeInto(nextHeader uint8, b []byte) int
}

var _ IPv6SerializableExtHdr = (*IPv6SerializableHopByHopExtHdr)(nil)

// IPv6SerializableHopByHopExtHdr implements serialization of the Hop by Hop
// options extension header.
type IPv6SerializableHopByHopExtHdr []IPv6SerializableHopByHopOption

const (
	// ipv6HopByHopExtHdrNextHeaderOffset is the offset of the next header field
	// in a hop by hop extension header as defined in RFC 8200 section 4.3.
	ipv6HopByHopExtHdrNextHeaderOffset = 0

	// ipv6HopByHopExtHdrLengthOffset is the offset of the length field in a hop
	// by hop extension header as defined in RFC 8200 section 4.3.
	ipv6HopByHopExtHdrLengthOffset = 1

	// ipv6HopByHopExtHdrPayloadOffset is the offset of the options in a hop by
	// hop extension header as defined in RFC 8200 section 4.3.
	ipv6HopByHopExtHdrOptionsOffset = 2

	// ipv6HopByHopExtHdrUnaccountedLenWords is the implicit number of 8-octet
	// words in a hop by hop extension header's length field, as stated in RFC
	// 8200 section 4.3:
	//   Length of the Hop-by-Hop Options header in 8-octet units,
	//   not including the first 8 octets.
	ipv6HopByHopExtHdrUnaccountedLenWords = 1
)

// identifier implements IPv6SerializableExtHdr.
func (IPv6SerializableHopByHopExtHdr) identifier() IPv6ExtensionHeaderIdentifier {
	return IPv6HopByHopOptionsExtHdrIdentifier
}

// length implements IPv6SerializableExtHdr.
func (h IPv6SerializableHopByHopExtHdr) length() int {
	var total int
	for _, opt := range h {
		align, alignOffset := opt.alignment()
		total += ipv6OptionsAlignmentPadding(total, align, alignOffset)
		total += ipv6ExtHdrOptionPayloadOffset + int(opt.length())
	}
	// Account for next header and total length fields and add padding.
	return padIPv6OptionsLength(ipv6HopByHopExtHdrOptionsOffset + total)
}

// serializeInto implements IPv6SerializableExtHdr.
func (h IPv6SerializableHopByHopExtHdr) serializeInto(nextHeader uint8, b []byte) int {
	optBuffer := b[ipv6HopByHopExtHdrOptionsOffset:]
	totalLength := ipv6HopByHopExtHdrOptionsOffset
	for _, opt := range h {
		// Calculate alignment requirements and pad buffer if necessary.
		align, alignOffset := opt.alignment()
		padLen := ipv6OptionsAlignmentPadding(totalLength, align, alignOffset)
		if padLen != 0 {
			padIPv6Option(optBuffer[:padLen])
			totalLength += padLen
			optBuffer = optBuffer[padLen:]
		}

		l := opt.serializeInto(optBuffer[ipv6ExtHdrOptionPayloadOffset:])
		optBuffer[ipv6ExtHdrOptionTypeOffset] = uint8(opt.identifier())
		optBuffer[ipv6ExtHdrOptionLengthOffset] = l
		l += ipv6ExtHdrOptionPayloadOffset
		totalLength += int(l)
		optBuffer = optBuffer[l:]
	}
	padded := padIPv6OptionsLength(totalLength)
	if padded != totalLength {
		padIPv6Option(optBuffer[:padded-totalLength])
		totalLength = padded
	}
	wordsLen := totalLength/ipv6ExtHdrLenBytesPerUnit - ipv6HopByHopExtHdrUnaccountedLenWords
	if wordsLen > math.MaxUint8 {
		panic(fmt.Sprintf("IPv6 hop by hop options too large: %d+1 64-bit words", wordsLen))
	}
	b[ipv6HopByHopExtHdrNextHeaderOffset] = nextHeader
	b[ipv6HopByHopExtHdrLengthOffset] = uint8(wordsLen)
	return totalLength
}

// IPv6SerializableHopByHopOption provides serialization for hop by hop options.
type IPv6SerializableHopByHopOption interface {
	// identifier returns the option identifier of this Hop by Hop option.
	identifier() IPv6ExtHdrOptionIdentifier

	// length returns the *payload* size of the option (not considering the type
	// and length fields).
	length() uint8

	// alignment returns the alignment requirements from this option.
	//
	// Alignment requirements take the form [align]n + offset as specified in
	// RFC 8200 section 4.2. The alignment requirement is on the offset between
	// the option type byte and the start of the hop by hop header.
	//
	// align must be a power of 2.
	alignment() (align int, offset int)

	// serializeInto serializes the receiver into the provided byte
	// buffer.
	//
	// Note, the caller MUST provide a byte buffer with size of at least
	// length. Implementers of this function may assume that the byte buffer
	// is of sufficient size. serializeInto MAY panic if the provided byte
	// buffer is not of sufficient size.
	//
	// serializeInto will return the number of bytes that was used to
	// serialize the receiver. Implementers must only use the number of
	// bytes required to serialize the receiver. Callers MAY provide a
	// larger buffer than required to serialize into.
	serializeInto([]byte) uint8
}

var _ IPv6SerializableHopByHopOption = (*IPv6RouterAlertOption)(nil)

// IPv6RouterAlertOption is the IPv6 Router alert Hop by Hop option defined in
// RFC 2711 section 2.1.
type IPv6RouterAlertOption struct {
	Value IPv6RouterAlertValue
}

// IPv6RouterAlertValue is the payload of an IPv6 Router Alert option.
type IPv6RouterAlertValue uint16

const (
	// IPv6RouterAlertMLD indicates a datagram containing a Multicast Listener
	// Discovery message as defined in RFC 2711 section 2.1.
	IPv6RouterAlertMLD IPv6RouterAlertValue = 0
	// IPv6RouterAlertRSVP indicates a datagram containing an RSVP message as
	// defined in RFC 2711 section 2.1.
	IPv6RouterAlertRSVP IPv6RouterAlertValue = 1
	// IPv6RouterAlertActiveNetworks indicates a datagram containing an Active
	// Networks message as defined in RFC 2711 section 2.1.
	IPv6RouterAlertActiveNetworks IPv6RouterAlertValue = 2

	// ipv6RouterAlertPayloadLength is the length of the Router Alert payload
	// as defined in RFC 2711.
	ipv6RouterAlertPayloadLength = 2

	// ipv6RouterAlertAlignmentRequirement is the alignment requirement for the
	// Router Alert option defined as 2n+0 in RFC 2711.
	ipv6RouterAlertAlignmentRequirement = 2

	// ipv6RouterAlertAlignmentOffsetRequirement is the alignment offset
	// requirement for the Router Alert option defined as 2n+0 in RFC 2711 section
	// 2.1.
	ipv6RouterAlertAlignmentOffsetRequirement = 0
)

// UnknownAction implements IPv6ExtHdrOption.
func (*IPv6RouterAlertOption) UnknownAction() IPv6OptionUnknownAction {
	return ipv6UnknownActionFromIdentifier(ipv6RouterAlertHopByHopOptionIdentifier)
}

// isIPv6ExtHdrOption implements IPv6ExtHdrOption.
func (*IPv6RouterAlertOption) isIPv6ExtHdrOption() {}

// identifier implements IPv6SerializableHopByHopOption.
func (*IPv6RouterAlertOption) identifier() IPv6ExtHdrOptionIdentifier {
	return ipv6RouterAlertHopByHopOptionIdentifier
}

// length implements IPv6SerializableHopByHopOption.
func (*IPv6RouterAlertOption) length() uint8 {
	return ipv6RouterAlertPayloadLength
}

// alignment implements IPv6SerializableHopByHopOption.
func (*IPv6RouterAlertOption) alignment() (int, int) {
	// From RFC 2711 section 2.1:
	//   Alignment requirement: 2n+0.
	return ipv6RouterAlertAlignmentRequirement, ipv6RouterAlertAlignmentOffsetRequirement
}

// serializeInto implements IPv6SerializableHopByHopOption.
func (o *IPv6RouterAlertOption) serializeInto(b []byte) uint8 {
	binary.BigEndian.PutUint16(b, uint16(o.Value))
	return ipv6RouterAlertPayloadLength
}

// IPv6ExtHdrSerializer provides serialization of IPv6 extension headers.
type IPv6ExtHdrSerializer []IPv6SerializableExtHdr

// Serialize serializes the provided list of IPv6 extension headers into b.
//
// Note, b must be of sufficient size to hold all the headers in s. See
// IPv6ExtHdrSerializer.Length for details on the getting the total size of a
// serialized IPv6ExtHdrSerializer.
//
// Serialize may panic if b is not of sufficient size to hold all the options
// in s.
//
// Serialize takes the transportProtocol value to be used as the last extension
// header's Next Header value and returns the header identifier of the first
// serialized extension header and the total serialized length.
func (s IPv6ExtHdrSerializer) Serialize(transportProtocol tcpip.TransportProtocolNumber, b []byte) (uint8, int) {
	nextHeader := uint8(transportProtocol)
	if len(s) == 0 {
		return nextHeader, 0
	}
	var totalLength int
	for i, h := range s[:len(s)-1] {
		length := h.serializeInto(uint8(s[i+1].identifier()), b)
		b = b[length:]
		totalLength += length
	}
	totalLength += s[len(s)-1].serializeInto(nextHeader, b)
	return uint8(s[0].identifier()), totalLength
}

// Length returns the total number of bytes required to serialize the extension
// headers.
func (s IPv6ExtHdrSerializer) Length() int {
	var totalLength int
	for _, h := range s {
		totalLength += h.length()
	}
	return totalLength
}
