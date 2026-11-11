package core

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/chi"
	"github.com/metacubex/chi/render"
	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
	"github.com/oschwald/maxminddb-golang"
)

type geoResource struct {
	update  func() error
	install func(data []byte) error
	url     func() string
	setUrl  func(string)
	path    func() string
}

var geoResources = map[string]geoResource{
	"MMDB":    {update: updater.UpdateMMDB, install: installMMDB, url: geodata.MmdbUrl, setUrl: geodata.SetMmdbUrl, path: constant.Path.MMDB},
	"ASN":     {update: updater.UpdateASN, install: installASN, url: geodata.ASNUrl, setUrl: geodata.SetASNUrl, path: constant.Path.ASN},
	"GEOIP":   {update: updater.UpdateGeoIp, install: installGeoIP, url: geodata.GeoIpUrl, setUrl: geodata.SetGeoIpUrl, path: constant.Path.GeoIP},
	"GEOSITE": {update: updater.UpdateGeoSite, install: installGeoSite, url: geodata.GeoSiteUrl, setUrl: geodata.SetGeoSiteUrl, path: constant.Path.GeoSite},
}

const geoDownloadTimeout = 90 * time.Second

// mihomo's updaters read a download whole, however large, under mihomo's own
// certificate policy; the core downloads the file within its size limit and
// under the app's policy, and installs it as they would.
func (resource geoResource) run() error {
	if resource.install == nil {
		return resource.update()
	}
	name := filepath.Base(resource.path())
	data, err := downloadBytes(resource.url(), geoDownloadTimeout, skipCertVerify.Load())
	if err == nil && len(data) == 0 {
		err = fmt.Errorf("no data")
	}
	if err != nil {
		return fmt.Errorf("can't download %s: %w", name, err)
	}
	if current, err := os.ReadFile(resource.path()); err == nil && bytes.Equal(current, data) {
		return nil
	}
	if err := resource.install(data); err != nil {
		return fmt.Errorf("can't install %s: %w", name, err)
	}
	return nil
}

func installMMDB(data []byte) error {
	return installMaxMind(data, constant.Path.MMDB(), func() { mmdb.IPInstance().Reader.Close() }, mmdb.ReloadIP)
}

func installASN(data []byte) error {
	return installMaxMind(data, constant.Path.ASN(), func() { mmdb.ASNInstance().Reader.Close() }, mmdb.ReloadASN)
}

func installMaxMind(data []byte, path string, closeLoaded func(), reload func()) error {
	validate := func(staged string) error {
		instance, err := maxminddb.Open(staged)
		if err == nil {
			err = instance.Close()
		}
		return err
	}
	return replaceGeoFile(path, data, validate, mappedReaderRelease(path, closeLoaded), reload)
}

// Windows will not rename over a mapped file, so its reader is closed first.
// Elsewhere the rename leaves the old mapping to lookups still reading it, and
// maxminddb's finalizer unmaps it once no lookup holds the reader: closing it
// here could unmap it from under one, which takes the Core down.
var closesMappedFile = runtime.GOOS == "windows"

func mappedReaderRelease(path string, closeLoaded func()) func() {
	return func() {
		if !closesMappedFile {
			return
		}
		if _, err := os.Stat(path); err == nil {
			closeLoaded()
		}
	}
}

func installGeoIP(data []byte) error {
	return installGeodata(data, constant.Path.GeoIP(), func(loader geodata.Loader, staged []byte) error {
		_, err := loader.LoadIPByBytes(staged, "cn")
		return err
	}, geodata.ClearGeoIPCache)
}

func installGeoSite(data []byte) error {
	return installGeodata(data, constant.Path.GeoSite(), func(loader geodata.Loader, staged []byte) error {
		_, err := loader.LoadSiteByBytes(staged, "cn")
		return err
	}, geodata.ClearGeoSiteCache)
}

func installGeodata(data []byte, path string, check func(geodata.Loader, []byte) error, clearCache func()) error {
	validate := func(staged string) error {
		loader, err := geodata.GetGeoDataLoader("standard")
		if err != nil {
			return err
		}
		buf, err := os.ReadFile(staged)
		if err != nil {
			return err
		}
		return check(loader, buf)
	}
	return replaceGeoFile(path, data, validate, func() {}, clearCache)
}

// The new file is whole on disk before the file-mapped database is released;
// a failed rename leaves the old file for the reload to reopen.
func replaceGeoFile(path string, data []byte, validate func(staged string) error, release func(), reload func()) error {
	staged, err := writeSyncedTemp(path, data)
	if err != nil {
		return err
	}
	defer os.Remove(staged)
	if err := validate(staged); err != nil {
		return err
	}
	release()
	defer reload()
	return os.Rename(staged, path)
}

func writeSyncedTemp(path string, data []byte) (string, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", err
	}
	file, err := os.CreateTemp(filepath.Dir(path), filepath.Base(path)+".*.tmp")
	if err != nil {
		return "", err
	}
	_, err = file.Write(data)
	if err == nil {
		err = file.Chmod(0o644)
	}
	if err == nil {
		err = file.Sync()
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(file.Name())
		return "", err
	}
	return file.Name(), nil
}

// mihomo's updaters read these links without a lock, so an unchanged one is never rewritten.
func setGeoResourceUrl(geoType string, link string) {
	resource, exist := geoResources[strings.ToUpper(geoType)]
	if !exist {
		log.Warnln("geox-url: unknown geo resource %q", geoType)
		return
	}
	if link != "" && link != resource.url() {
		resource.setUrl(link)
	}
}

func claimGeoUpdate(geoType string) bool {
	return claimUpdate(geoUpdateScope + geoType)
}

func releaseGeoUpdate(geoType string) {
	releaseUpdate(geoUpdateScope + geoType)
}

func handleUpdateGeoData(geoType string) error {
	resource, exist := geoResources[geoType]
	if !exist {
		logError("updateGeoData: unknown geo resource %q", geoType)
		return fmt.Errorf("unknown geo resource: %s", geoType)
	}
	if !claimGeoUpdate(geoType) {
		return fmt.Errorf("geo update already in progress: %s", geoType)
	}
	safeGo("updateGeoData("+geoType+")", func() {
		defer releaseGeoUpdate(geoType)
		runGeoUpdate(geoType, resource)
	})
	return nil
}

// mihomo's updater returns nil for a download that matched the file it had,
// so whether the file changed is what tells an update from a skip.
func runGeoUpdate(geoType string, resource geoResource) error {
	sendMessage(GeoUpdateMessage, GeoUpdateStatus{Type: geoType, Updating: true})
	before := resource.stamp()
	err := resource.run()
	if err != nil {
		logError("updateGeoData(%s) error: %v", geoType, err)
	}
	onGeoUpdate(geoType, false, err == nil && resource.stamp() == before, err)
	return err
}

type fileStampValue struct {
	size    int64
	modTime time.Time
}

func (resource geoResource) stamp() fileStampValue {
	if resource.path == nil {
		return fileStampValue{}
	}
	info, err := os.Stat(resource.path())
	if err != nil {
		return fileStampValue{}
	}
	return fileStampValue{size: info.Size(), modTime: info.ModTime()}
}

func onGeoUpdate(geoType string, updating bool, skipped bool, updateErr error) {
	if updating {
		claimUpdateAs(geoUpdateScope+geoType, true)
	} else {
		releaseHookUpdate(geoUpdateScope + geoType)
		scheduleReclaimOwnership()
		if !skipped && updateErr == nil {
			changeRoute(routeMoved)
		}
	}
	status := GeoUpdateStatus{Type: geoType, Updating: updating, Skipped: skipped}
	if updateErr != nil {
		status.Error = updateErr.Error()
	}
	sendMessage(GeoUpdateMessage, status)
}

var (
	registerGeoUpdater = startGeoUpdater
	stopGeoUpdater     = stopGeoUpdaterRun
)

// mihomo starts its own geo updater only in its binary; the library leaves
// it to the host, which wants to stop it with the core and hear how each
// database fared.
var geoUpdaterRun struct {
	sync.Mutex
	cancel context.CancelFunc
}

// More hours overflow a Duration into a negative one, which fires back to back.
const maxGeoUpdateIntervalHours = math.MaxInt64 / int64(time.Hour)

func startGeoUpdater() {
	interval := updater.GeoUpdateInterval()
	if interval <= 0 || int64(interval) > maxGeoUpdateIntervalHours {
		log.Warnln("[GEO] invalid update interval: %d", interval)
		return
	}
	stopGeoUpdaterRun()
	ctx, cancel := context.WithCancel(context.Background())
	geoUpdaterRun.Lock()
	geoUpdaterRun.cancel = cancel
	geoUpdaterRun.Unlock()
	go runGeoUpdater(ctx, time.Duration(interval)*time.Hour)
}

func stopGeoUpdaterRun() {
	geoUpdaterRun.Lock()
	defer geoUpdaterRun.Unlock()
	if geoUpdaterRun.cancel != nil {
		geoUpdaterRun.cancel()
		geoUpdaterRun.cancel = nil
	}
}

func runGeoUpdater(ctx context.Context, interval time.Duration) {
	first := interval - time.Since(lastGeoUpdateTime())
	if first < 0 {
		first = 0
	}
	timer := time.NewTimer(first)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			updateGeoResources()
			timer.Reset(interval)
		}
	}
}

func lastGeoUpdateTime() time.Time {
	for _, path := range []string{
		constant.Path.GeoIP(), constant.Path.MMDB(), constant.Path.ASN(), constant.Path.GeoSite(),
	} {
		if info, err := os.Stat(path); err == nil {
			return info.ModTime()
		}
	}
	return time.Time{}
}

func enabledGeoResources() []string {
	var names []string
	if geodata.GeoIpEnable() {
		if geodata.GeodataMode() {
			names = append(names, "GEOIP")
		} else {
			names = append(names, "MMDB")
		}
	}
	if geodata.ASNEnable() {
		names = append(names, "ASN")
	}
	if geodata.GeoSiteEnable() {
		names = append(names, "GEOSITE")
	}
	return names
}

// A resource a manual update holds is left to it.
func updateGeoResources() error {
	var errs []error
	for _, name := range enabledGeoResources() {
		if !claimUpdateAs(geoUpdateScope+name, true) {
			continue
		}
		errs = append(errs, runGeoUpdate(name, geoResources[name]))
	}
	return errors.Join(errs...)
}

// The controller's geo endpoints would run mihomo's updater on the core's files.
func init() {
	route.Register(func(r chi.Router) {
		r.Post("/configs/geo", serveGeoUpdate)
		r.Post("/upgrade/geo", serveGeoUpdate)
	})
}

var controllerGeoUpdate = updateGeoResources

func serveGeoUpdate(w http.ResponseWriter, r *http.Request) {
	if err := controllerGeoUpdate(); err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.JSON(w, r, render.M{"message": err.Error()})
		return
	}
	render.NoContent(w, r)
}

func syncGeoUpdater(autoUpdate *bool, interval *int) {
	changed := false
	if autoUpdate != nil && *autoUpdate != updater.GeoAutoUpdate() {
		updater.SetGeoAutoUpdate(*autoUpdate)
		changed = true
	}
	if interval != nil && *interval != updater.GeoUpdateInterval() {
		updater.SetGeoUpdateInterval(*interval)
		changed = true
	}
	if changed {
		reconcileGeoUpdater()
	}
}

func reconcileGeoUpdater() {
	if updater.GeoAutoUpdate() {
		registerGeoUpdater()
		return
	}
	stopGeoUpdater()
}
