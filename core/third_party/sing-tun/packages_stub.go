//go:build !android

package tun

import "os"

func NewPackageManager(options PackageManagerOptions) (PackageManager, error) {
	return nil, os.ErrInvalid
}
