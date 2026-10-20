package tun

import (
	"bytes"
	"encoding/xml"
	"io"
	"os"
	"strconv"

	"github.com/metacubex/fswatch"
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/abx"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
)

type packageManager struct {
	callback        PackageManagerCallback
	logger          logger.Logger
	watcher         *fswatch.Watcher
	idByPackage     map[string]uint32
	sharedByPackage map[string]uint32
	packageById     map[uint32][]string
	sharedById      map[uint32]string
}

func NewPackageManager(options PackageManagerOptions) (PackageManager, error) {
	return &packageManager{
		callback: options.Callback,
		logger:   options.Logger,
	}, nil
}

func (m *packageManager) Start() error {
	err := m.updatePackages()
	if err != nil {
		return E.Cause(err, "read packages list")
	}
	err = m.startWatcher()
	if err != nil {
		m.logger.Error(E.Cause(err, "create watcher for packages list"))
	}
	return nil
}

func (m *packageManager) startWatcher() error {
	watcher, err := fswatch.NewWatcher(fswatch.Options{
		Path:     []string{"/data/system/packages.xml"},
		Direct:   true,
		Callback: m.packagesUpdated,
		Logger:   m.logger,
	})
	if err != nil {
		return err
	}
	err = watcher.Start()
	if err != nil {
		return err
	}
	m.watcher = watcher
	return nil
}

func (m *packageManager) packagesUpdated(path string) {
	err := m.updatePackages()
	if err != nil {
		m.logger.Error(E.Cause(err, "update packages"))
	}
}

func (m *packageManager) Close() error {
	return common.Close(common.PtrOrNil(m.watcher))
}

func (m *packageManager) IDByPackage(packageName string) (uint32, bool) {
	id, loaded := m.idByPackage[packageName]
	return id, loaded
}

func (m *packageManager) IDBySharedPackage(sharedPackage string) (uint32, bool) {
	id, loaded := m.sharedByPackage[sharedPackage]
	return id, loaded
}

func (m *packageManager) PackageByID(id uint32) (string, bool) {
	packageNames, loaded := m.packageById[id]
	if !loaded || len(packageNames) == 0 {
		return "", false
	}
	return packageNames[0], true
}

func (m *packageManager) PackagesByID(id uint32) ([]string, bool) {
	packageNames, loaded := m.packageById[id]
	return packageNames, loaded
}

func (m *packageManager) SharedPackageByID(id uint32) (string, bool) {
	sharedPackage, loaded := m.sharedById[id]
	return sharedPackage, loaded
}

func (m *packageManager) updatePackages() error {
	packagesData, err := os.ReadFile("/data/system/packages.xml")
	if err != nil {
		return err
	}
	var decoder *xml.Decoder
	reader, ok := abx.NewReader(packagesData)
	if ok {
		decoder = xml.NewTokenDecoder(reader)
	} else {
		decoder = xml.NewDecoder(bytes.NewReader(packagesData))
	}
	return m.decodePackages(decoder)
}

func (m *packageManager) decodePackages(decoder *xml.Decoder) error {
	idByPackage := make(map[string]uint32)
	sharedByPackage := make(map[string]uint32)
	packageById := make(map[uint32][]string)
	sharedById := make(map[uint32]string)
	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		} else if err != nil {
			return err
		}

		element, isStart := token.(xml.StartElement)
		if !isStart {
			continue
		}

		switch element.Name.Local {
		case "package":
			var name string
			var userID uint64
			for _, attr := range element.Attr {
				switch attr.Name.Local {
				case "name":
					name = attr.Value
				case "userId", "sharedUserId":
					userID, err = strconv.ParseUint(attr.Value, 10, 32)
					if err != nil {
						return err
					}
				}
			}
			if userID == 0 && name == "" {
				continue
			}
			idByPackage[name] = uint32(userID)
			packageById[uint32(userID)] = append(packageById[uint32(userID)], name)
		case "shared-user":
			var name string
			var userID uint64
			for _, attr := range element.Attr {
				switch attr.Name.Local {
				case "name":
					name = attr.Value
				case "userId":
					userID, err = strconv.ParseUint(attr.Value, 10, 32)
					if err != nil {
						return err
					}
				}
			}
			if userID == 0 && name == "" {
				continue
			}
			sharedByPackage[name] = uint32(userID)
			sharedById[uint32(userID)] = name
		}
	}
	m.idByPackage = idByPackage
	m.sharedByPackage = sharedByPackage
	m.packageById = packageById
	m.sharedById = sharedById
	m.callback.OnPackagesUpdated(len(packageById), len(sharedById))
	return nil
}
