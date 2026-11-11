//go:build windows

package winsys

import (
	"golang.org/x/sys/windows"
)

const (
	AF_INET  = 2
	AF_INET6 = 23
)

const (
	MAX_MODULE_NAME32 = 255
	MAX_PATH          = 260
)

// https://docs.microsoft.com/en-us/windows/desktop/api/tlhelp32/nf-tlhelp32-createtoolhelp32snapshot
const (
	TH32CS_SNAPHEAPLIST = 0x00000001
	TH32CS_SNAPPROCESS  = 0x00000002
	TH32CS_SNAPTHREAD   = 0x00000004
	TH32CS_SNAPMODULE   = 0x00000008
	TH32CS_SNAPMODULE32 = 0x00000010
	TH32CS_INHERIT      = 0x80000000
	TH32CS_SNAPALL      = TH32CS_SNAPHEAPLIST | TH32CS_SNAPMODULE | TH32CS_SNAPPROCESS | TH32CS_SNAPTHREAD
)

const (
	MAX_ADAPTER_NAME       = 128
	MAX_INTERFACE_NAME_LEN = 256
	MAXLEN_PHYSADDR        = 8
	MAXLEN_IFDESCR         = 256
)

const (
	ERROR_INSUFFICIENT_BUFFER = 122
)

const (
	RPC_C_AUTHN_DEFAULT       uint32 = 0xFFFFFFFF
	FWPM_SESSION_FLAG_DYNAMIC uint32 = 0x00000001
)

const (
	FWP_MATCH_EQUAL                  uint32 = 0
	FWP_MATCH_GREATER                       = (FWP_MATCH_EQUAL + 1)
	FWP_MATCH_LESS                          = (FWP_MATCH_GREATER + 1)
	FWP_MATCH_GREATER_OR_EQUAL              = (FWP_MATCH_LESS + 1)
	FWP_MATCH_LESS_OR_EQUAL                 = (FWP_MATCH_GREATER_OR_EQUAL + 1)
	FWP_MATCH_RANGE                         = (FWP_MATCH_LESS_OR_EQUAL + 1)
	FWP_MATCH_FLAGS_ALL_SET                 = (FWP_MATCH_RANGE + 1)
	FWP_MATCH_FLAGS_ANY_SET                 = (FWP_MATCH_FLAGS_ALL_SET + 1)
	FWP_MATCH_FLAGS_NONE_SET                = (FWP_MATCH_FLAGS_ANY_SET + 1)
	FWP_MATCH_EQUAL_CASE_INSENSITIVE        = (FWP_MATCH_FLAGS_NONE_SET + 1)
	FWP_MATCH_NOT_EQUAL                     = (FWP_MATCH_EQUAL_CASE_INSENSITIVE + 1)
	FWP_MATCH_PREFIX                        = (FWP_MATCH_NOT_EQUAL + 1)
	FWP_MATCH_NOT_PREFIX                    = (FWP_MATCH_PREFIX + 1)
	FWP_MATCH_TYPE_MAX                      = (FWP_MATCH_NOT_PREFIX + 1)
)

const (
	FWP_EMPTY                         uint32 = 0
	FWP_UINT8                                = (FWP_EMPTY + 1)
	FWP_UINT16                               = (FWP_UINT8 + 1)
	FWP_UINT32                               = (FWP_UINT16 + 1)
	FWP_UINT64                               = (FWP_UINT32 + 1)
	FWP_INT8                                 = (FWP_UINT64 + 1)
	FWP_INT16                                = (FWP_INT8 + 1)
	FWP_INT32                                = (FWP_INT16 + 1)
	FWP_INT64                                = (FWP_INT32 + 1)
	FWP_FLOAT                                = (FWP_INT64 + 1)
	FWP_DOUBLE                               = (FWP_FLOAT + 1)
	FWP_BYTE_ARRAY16_TYPE                    = (FWP_DOUBLE + 1)
	FWP_BYTE_BLOB_TYPE                       = (FWP_BYTE_ARRAY16_TYPE + 1)
	FWP_SID                                  = (FWP_BYTE_BLOB_TYPE + 1)
	FWP_SECURITY_DESCRIPTOR_TYPE             = (FWP_SID + 1)
	FWP_TOKEN_INFORMATION_TYPE               = (FWP_SECURITY_DESCRIPTOR_TYPE + 1)
	FWP_TOKEN_ACCESS_INFORMATION_TYPE        = (FWP_TOKEN_INFORMATION_TYPE + 1)
	FWP_UNICODE_STRING_TYPE                  = (FWP_TOKEN_ACCESS_INFORMATION_TYPE + 1)
	FWP_BYTE_ARRAY6_TYPE                     = (FWP_UNICODE_STRING_TYPE + 1)
	FWP_BITMAP_INDEX_TYPE                    = (FWP_BYTE_ARRAY6_TYPE + 1)
	FWP_BITMAP_ARRAY64_TYPE                  = (FWP_BITMAP_INDEX_TYPE + 1)
	FWP_SINGLE_DATA_TYPE_MAX                 = 0xff
	FWP_V4_ADDR_MASK                         = (FWP_SINGLE_DATA_TYPE_MAX + 1)
	FWP_V6_ADDR_MASK                         = (FWP_V4_ADDR_MASK + 1)
	FWP_RANGE_TYPE                           = (FWP_V6_ADDR_MASK + 1)
	FWP_DATA_TYPE_MAX                        = (FWP_RANGE_TYPE + 1)
)

var FWPM_CONDITION_IP_PROTOCOL = windows.GUID{
	Data1: 0x3971ef2b,
	Data2: 0x623e,
	Data3: 0x4f9a,
	Data4: [8]byte{0x8c, 0xb1, 0x6e, 0x79, 0xb8, 0x06, 0xb9, 0xa7},
}

var FWPM_CONDITION_IP_REMOTE_PORT = windows.GUID{
	Data1: 0xc35a604d,
	Data2: 0xd22b,
	Data3: 0x4e1a,
	Data4: [8]byte{0x91, 0xb4, 0x68, 0xf6, 0x74, 0xee, 0x67, 0x4b},
}

var FWPM_CONDITION_IP_LOCAL_PORT = windows.GUID{
	Data1: 0x0c1ba1af,
	Data2: 0x5765,
	Data3: 0x453f,
	Data4: [8]byte{0xaf, 0x22, 0xa8, 0xf7, 0x91, 0xac, 0x77, 0x5b},
}

var FWPM_CONDITION_IP_REMOTE_ADDRESS = windows.GUID{
	Data1: 0xb235ae9a,
	Data2: 0x1d64,
	Data3: 0x49b8,
	Data4: [8]byte{0xa4, 0x4c, 0x5f, 0xf3, 0xd9, 0x09, 0x50, 0x45},
}

var (
	FWPM_CONDITION_ICMP_TYPE = FWPM_CONDITION_IP_LOCAL_PORT
	FWPM_CONDITION_ICMP_CODE = FWPM_CONDITION_IP_REMOTE_PORT
)

var FWPM_LAYER_ALE_AUTH_CONNECT_V4 = windows.GUID{
	Data1: 0xc38d57d1,
	Data2: 0x05a7,
	Data3: 0x4c33,
	Data4: [8]byte{0x90, 0x4f, 0x7f, 0xbc, 0xee, 0xe6, 0x0e, 0x82},
}

var FWPM_CONDITION_LOCAL_INTERFACE_INDEX = windows.GUID{
	Data1: 0x667fd755,
	Data2: 0xd695,
	Data3: 0x434a,
	Data4: [8]byte{0x8a, 0xf5, 0xd3, 0x83, 0x5a, 0x12, 0x59, 0xbc},
}

var FWPM_LAYER_ALE_AUTH_CONNECT_V6 = windows.GUID{
	Data1: 0x4a72393b,
	Data2: 0x319f,
	Data3: 0x44bc,
	Data4: [8]byte{0x84, 0xc3, 0xba, 0x54, 0xdc, 0xb3, 0xb6, 0xb4},
}

var FWPM_CONDITION_ALE_APP_ID = windows.GUID{
	Data1: 0xd78e1e87,
	Data2: 0x8644,
	Data3: 0x4ea5,
	Data4: [8]byte{0x94, 0x37, 0xd8, 0x09, 0xec, 0xef, 0xc9, 0x71},
}

const (
	IPPROTO_UDP    uint32 = 17
	IPPROTO_ICMPV6 uint32 = 58
)

const (
	FWP_ACTION_FLAG_TERMINATING uint32 = 0x00001000
	FWP_ACTION_BLOCK            uint32 = (0x00000001 | FWP_ACTION_FLAG_TERMINATING)
	FWP_ACTION_PERMIT           uint32 = (0x00000002 | FWP_ACTION_FLAG_TERMINATING)
)

const (
	FWPM_FILTER_FLAG_NONE                                = 0x00000000
	FWPM_FILTER_FLAG_PERSISTENT                          = 0x00000001
	FWPM_FILTER_FLAG_BOOTTIME                            = 0x00000002
	FWPM_FILTER_FLAG_HAS_PROVIDER_CONTEXT                = 0x00000004
	FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT                  = 0x00000008
	FWPM_FILTER_FLAG_PERMIT_IF_CALLOUT_UNREGISTERED      = 0x00000010
	FWPM_FILTER_FLAG_DISABLED                            = 0x00000020
	FWPM_FILTER_FLAG_INDEXED                             = 0x00000040
	FWPM_FILTER_FLAG_HAS_SECURITY_REALM_PROVIDER_CONTEXT = 0x00000080
	FWPM_FILTER_FLAG_SYSTEMOS_ONLY                       = 0x00000100
	FWPM_FILTER_FLAG_GAMEOS_ONLY                         = 0x00000200
	FWPM_FILTER_FLAG_SILENT_MODE                         = 0x00000400
	FWPM_FILTER_FLAG_IPSEC_NO_ACQUIRE_INITIATE           = 0x00000800
)
