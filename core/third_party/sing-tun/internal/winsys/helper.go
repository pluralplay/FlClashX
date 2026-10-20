//go:build windows

package winsys

import (
	"os"
	"unsafe"

	"github.com/metacubex/sing/common"

	"golang.org/x/sys/windows"
)

func CreateDisplayData(name, description string) FWPM_DISPLAY_DATA0 {
	namePtr, err := windows.UTF16PtrFromString(name)
	common.Must(err)

	descriptionPtr, err := windows.UTF16PtrFromString(description)
	common.Must(err)

	return FWPM_DISPLAY_DATA0{
		Name:        namePtr,
		Description: descriptionPtr,
	}
}

func GetCurrentProcessAppID() (*FWP_BYTE_BLOB, error) {
	currentFile, err := os.Executable()
	if err != nil {
		return nil, err
	}

	curFilePtr, err := windows.UTF16PtrFromString(currentFile)
	if err != nil {
		return nil, err
	}

	windows.GetCurrentProcessId()

	var appID *FWP_BYTE_BLOB
	err = FwpmGetAppIdFromFileName0(curFilePtr, unsafe.Pointer(&appID))
	if err != nil {
		return nil, err
	}
	return appID, nil
}
