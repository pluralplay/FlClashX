package winsys

// https://docs.microsoft.com/en-us/windows/desktop/api/fwpmu/nf-fwpmu-fwpmengineopen0
//sys   FwpmEngineOpen0(serverName *uint16, authnService uint32, authIdentity *uintptr, session *FWPM_SESSION0, engineHandle unsafe.Pointer) (err error) [failretval!=0] = fwpuclnt.FwpmEngineOpen0

// https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmengineclose0
//sys   FwpmEngineClose0(engineHandle uintptr) (err error) [failretval!=0] = fwpuclnt.FwpmEngineClose0

// https://docs.microsoft.com/en-us/windows/desktop/api/fwpmu/nf-fwpmu-fwpmsublayeradd0
//sys   FwpmSubLayerAdd0(engineHandle uintptr, subLayer *FWPM_SUBLAYER0, sd uintptr) (err error) [failretval!=0] = fwpuclnt.FwpmSubLayerAdd0

// https://docs.microsoft.com/en-us/windows/desktop/api/fwpmu/nf-fwpmu-fwpmfilteradd0
//sys   FwpmFilterAdd0(engineHandle uintptr, filter *FWPM_FILTER0, sd uintptr, id *uint64) (err error) [failretval!=0] = fwpuclnt.FwpmFilterAdd0

// https://docs.microsoft.com/en-us/windows/desktop/api/fwpmu/nf-fwpmu-fwpmgetappidfromfilename0
//sys	FwpmGetAppIdFromFileName0(fileName *uint16, appID unsafe.Pointer) (err error) [failretval!=0] = fwpuclnt.FwpmGetAppIdFromFileName0

// https://docs.microsoft.com/en-us/windows/desktop/api/fwpmu/nf-fwpmu-fwpmfreememory0
//sys	FwpmFreeMemory0(p unsafe.Pointer) = fwpuclnt.FwpmFreeMemory0
