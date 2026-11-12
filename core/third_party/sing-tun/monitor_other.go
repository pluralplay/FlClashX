//go:build !(linux || windows || darwin)

package tun

import (
	"os"

	"github.com/metacubex/sing/common/logger"
)

func NewNetworkUpdateMonitor(logger logger.Logger) (NetworkUpdateMonitor, error) {
	return nil, os.ErrInvalid
}

func NewDefaultInterfaceMonitor(networkMonitor NetworkUpdateMonitor, logger logger.Logger, options DefaultInterfaceMonitorOptions) (DefaultInterfaceMonitor, error) {
	return nil, os.ErrInvalid
}
