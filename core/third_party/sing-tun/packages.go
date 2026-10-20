package tun

import "github.com/metacubex/sing/common/logger"

type PackageManager interface {
	Start() error
	Close() error
	IDByPackage(packageName string) (uint32, bool)
	IDBySharedPackage(sharedPackage string) (uint32, bool)
	PackageByID(id uint32) (string, bool)
	PackagesByID(id uint32) ([]string, bool)
	SharedPackageByID(id uint32) (string, bool)
}

type PackageManagerOptions struct {
	Callback PackageManagerCallback

	// Logger is the logger to log errors
	// optional
	Logger logger.Logger
}

type PackageManagerCallback interface {
	OnPackagesUpdated(packages int, sharedUsers int)
}
