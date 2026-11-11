package winsys

import (
	"golang.org/x/sys/windows"
)

type (
	BOOL      int32
	HANDLE    uintptr
	DWORD     uint32
	PDWORD    uintptr
	ULONG     uint32
	ULONG_PTR uintptr
	HMODULE   HANDLE
)

type MIB_IPFORWARDROW struct {
	ForwardDest      uint32
	ForwardMask      uint32
	ForwardPolicy    uint32
	ForwardNextHop   uint32
	ForwardIfIndex   uint32
	ForwardType      uint32
	ForwardProto     uint32
	ForwardAge       uint32
	ForwardNextHopAS uint32
	ForwardMetric1   uint32
	ForwardMetric2   uint32
	ForwardMetric3   uint32
	ForwardMetric4   uint32
	ForwardMetric5   uint32
}

type FWPM_DISPLAY_DATA0 struct {
	Name        *uint16
	Description *uint16
}

type FWPM_SESSION0 struct {
	SessionKey           windows.GUID
	DisplayData          FWPM_DISPLAY_DATA0
	Flags                uint32
	TxnWaitTimeoutInMSec uint32
	ProcessId            uint32
	Sid                  *windows.SID
	Username             *uint16
	KernelMode           int32
}

type FWP_BYTE_BLOB struct {
	size uint32
	data *uint8
}

type FWPM_SUBLAYER0 struct {
	SubLayerKey  windows.GUID // Windows type: GUID
	DisplayData  FWPM_DISPLAY_DATA0
	Flags        uint32
	ProviderKey  *windows.GUID // Windows type: *GUID
	ProviderData FWP_BYTE_BLOB
	Weight       uint16
}

type FWP_VALUE0 struct {
	Type  uint32
	Value uintptr
}

type FWP_CONDITION_VALUE0 FWP_VALUE0

type FWP_BYTE_ARRAY16 struct {
	ByteArray16 [16]uint8
}

type FWPM_FILTER_CONDITION0 struct {
	FieldKey       windows.GUID // Windows type: GUID
	MatchType      uint32
	ConditionValue FWP_CONDITION_VALUE0
}

type FWPM_ACTION0 struct {
	Type  uint32
	Value windows.GUID
}

type FWPM_FILTER0 struct {
	FilterKey           windows.GUID
	DisplayData         FWPM_DISPLAY_DATA0
	Flags               uint32
	ProviderKey         *windows.GUID
	ProviderData        FWP_BYTE_BLOB
	LayerKey            windows.GUID
	SubLayerKey         windows.GUID
	Weight              FWP_VALUE0
	NumFilterConditions uint32
	FilterCondition     *FWPM_FILTER_CONDITION0
	Action              FWPM_ACTION0
	Offset1             [4]byte
	Context             windows.GUID
	Reserved            *windows.GUID
	FilterId            uint64
	EffectiveWeight     FWP_VALUE0
}
