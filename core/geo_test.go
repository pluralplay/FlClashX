//go:build !cgo && !android

package core

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/route"
)

// One node whose records both mean "not found", then a metadata map of
// node_count 1, record_size 24 and ip_version 4.
func maxMindTestDatabase(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	buf.Write([]byte{0, 0, 1, 0, 0, 1})
	buf.Write(make([]byte, 16))
	buf.WriteString("\xab\xcd\xefMaxMind.com")
	buf.WriteByte(0xE3)
	buf.WriteString("\x4anode_count\xc1\x01")
	buf.WriteString("\x4brecord_size\xa1\x18")
	buf.WriteString("\x4aip_version\xa1\x04")
	return buf.Bytes()
}

func geoStatuses(t *testing.T, run func()) []GeoUpdateStatus {
	t.Helper()
	fake := &fakeConn{}
	previous := swapConn(fake)
	defer swapConn(previous)
	run()
	deadline := time.Now().Add(2 * time.Second)
	for {
		var statuses []GeoUpdateStatus
		for _, frame := range fake.frames(t) {
			var batch struct {
				Arguments []struct {
					Type MessageType     `json:"type"`
					Data GeoUpdateStatus `json:"data"`
				} `json:"arguments"`
			}
			if err := json.Unmarshal(frame, &batch); err != nil {
				t.Fatalf("frame is not a message batch: %v", err)
			}
			for _, message := range batch.Arguments {
				if message.Type == GeoUpdateMessage {
					statuses = append(statuses, message.Data)
				}
			}
		}
		if len(statuses) >= 2 || time.Now().After(deadline) {
			return statuses
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func stubGeoResource(t *testing.T, update func(path string) error) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "ASN.mmdb")
	if err := os.WriteFile(path, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-time.Hour)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	previous := geoResources["ASN"]
	geoResources["ASN"] = geoResource{
		update: func() error { return update(path) },
		url:    previous.url,
		setUrl: previous.setUrl,
		path:   func() string { return path },
	}
	t.Cleanup(func() { geoResources["ASN"] = previous })
	return path
}

func manualGeoUpdate(t *testing.T) []GeoUpdateStatus {
	t.Helper()
	return geoStatuses(t, func() {
		if err := handleUpdateGeoData("ASN"); err != nil {
			t.Fatalf("handleUpdateGeoData: %v", err)
		}
		waitForGeoRelease(t, "ASN")
	})
}

func waitForGeoRelease(t *testing.T, geoType string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for !claimGeoUpdate(geoType) {
		if time.Now().After(deadline) {
			t.Fatalf("%s update never released its claim", geoType)
		}
		time.Sleep(time.Millisecond)
	}
	releaseGeoUpdate(geoType)
}

func TestManualGeoUpdateReportsAnUnchangedFileAsSkipped(t *testing.T) {
	stubGeoResource(t, func(string) error { return nil })
	statuses := manualGeoUpdate(t)
	want := []GeoUpdateStatus{
		{Type: "ASN", Updating: true},
		{Type: "ASN", Skipped: true},
	}
	if len(statuses) != 2 || statuses[0] != want[0] || statuses[1] != want[1] {
		t.Fatalf("statuses = %+v, want %+v", statuses, want)
	}
}

func TestManualGeoUpdateReportsARewrittenFileAsUpdated(t *testing.T) {
	stubGeoResource(t, func(path string) error {
		return os.WriteFile(path, []byte("newer"), 0o644)
	})
	statuses := manualGeoUpdate(t)
	if len(statuses) != 2 || statuses[1] != (GeoUpdateStatus{Type: "ASN"}) {
		t.Fatalf("statuses = %+v, want an update that was not skipped", statuses)
	}
}

func TestManualGeoUpdateReportsTheError(t *testing.T) {
	stubGeoResource(t, func(string) error { return errors.New("offline") })
	statuses := manualGeoUpdate(t)
	if len(statuses) != 2 || statuses[1].Error != "offline" || statuses[1].Skipped {
		t.Fatalf("statuses = %+v, want the error reported", statuses)
	}
}

func TestTheGeoUpdaterRefusesAnIntervalThatOverflows(t *testing.T) {
	previous := updater.GeoUpdateInterval()
	t.Cleanup(func() {
		updater.SetGeoUpdateInterval(previous)
		stopGeoUpdaterRun()
	})
	stopGeoUpdaterRun()
	updater.SetGeoUpdateInterval(3000000)

	startGeoUpdater()

	geoUpdaterRun.Lock()
	running := geoUpdaterRun.cancel != nil
	geoUpdaterRun.Unlock()
	if running {
		t.Fatal("the updater runs on an interval that overflows into a negative duration")
	}
}

type geoSwapCalls struct {
	released, reloaded int
	seenOnRelease      string
	seenOnReload       string
}

func installedGeoFile(t *testing.T) (string, *geoSwapCalls, func(), func()) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "geo.db")
	if err := os.WriteFile(path, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	calls := &geoSwapCalls{}
	read := func() string {
		buf, _ := os.ReadFile(path)
		return string(buf)
	}
	release := func() { calls.released++; calls.seenOnRelease = read() }
	reload := func() { calls.reloaded++; calls.seenOnReload = read() }
	return path, calls, release, reload
}

func assertOnlyTheInstalledFile(t *testing.T, path string, want string) {
	t.Helper()
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil || len(entries) != 1 {
		t.Fatalf("directory holds %v, %v; want only the database", entries, err)
	}
	if buf, err := os.ReadFile(path); err != nil || string(buf) != want {
		t.Fatalf("database = %q, %v; want %q", buf, err, want)
	}
}

func TestAnInvalidMaxMindDownloadLeavesTheLoadedDatabase(t *testing.T) {
	path, calls, _, reload := installedGeoFile(t)

	if err := installMaxMind([]byte("not a database"), path, reload); err == nil {
		t.Fatal("an invalid database was installed")
	}

	assertOnlyTheInstalledFile(t, path, "old")
	if calls.released != 0 || calls.reloaded != 0 {
		t.Fatalf("calls = %+v, want the loaded reader left alone", calls)
	}
}

func TestAnInvalidGeodataDownloadLeavesTheInstalledFile(t *testing.T) {
	path, calls, _, reload := installedGeoFile(t)
	check := func(geodata.Loader, []byte) error { return errors.New("invalid") }

	if err := installGeodata([]byte("new"), path, check, reload); err == nil {
		t.Fatal("an invalid geodata file was installed")
	}

	assertOnlyTheInstalledFile(t, path, "old")
	if calls.reloaded != 0 {
		t.Fatalf("calls = %+v, want the cache kept", calls)
	}
}

func TestAGeoFileIsReplacedOnlyOnceTheNewOneIsWhole(t *testing.T) {
	path, calls, release, reload := installedGeoFile(t)

	if err := replaceGeoFile(path, []byte("new"), func(string) error { return nil }, release, reload); err != nil {
		t.Fatalf("replace: %v", err)
	}

	assertOnlyTheInstalledFile(t, path, "new")
	if calls.released != 1 || calls.seenOnRelease != "old" || calls.reloaded != 1 || calls.seenOnReload != "new" {
		t.Fatalf("calls = %+v, want the reader released over the old file and reloaded over the new", calls)
	}
}

func TestAGeoFileThatCannotBeStagedLeavesTheOldOne(t *testing.T) {
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("needs a directory its owner cannot write")
	}
	path, calls, release, reload := installedGeoFile(t)
	dir := filepath.Dir(path)
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })

	if err := replaceGeoFile(path, []byte("new"), func(string) error { return nil }, release, reload); err == nil {
		t.Fatal("staged into a directory it cannot write")
	}

	assertOnlyTheInstalledFile(t, path, "old")
	if calls.released != 0 || calls.reloaded != 0 {
		t.Fatalf("calls = %+v, want the reader left alone", calls)
	}
}

func TestAFailedGeoRenameLeavesNoStagedFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "geo.db")
	if err := os.MkdirAll(filepath.Join(path, "busy"), 0o755); err != nil {
		t.Fatal(err)
	}
	released, reloaded := 0, 0

	err := replaceGeoFile(path, []byte("new"), func(string) error { return nil }, func() { released++ }, func() { reloaded++ })

	if err == nil {
		t.Fatal("renamed over a directory")
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 1 {
		t.Fatalf("directory holds %v, want the staged file removed", entries)
	}
	if released != 1 || reloaded != 1 {
		t.Fatalf("released %d, reloaded %d; want the reader reopened after the failed swap", released, reloaded)
	}
}

func TestTheControllerGeoEndpointsRunTheCoresGuardedUpdate(t *testing.T) {
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserve a port: %v", err)
	}
	address := probe.Addr().String()
	_ = probe.Close()
	route.ReCreateServer(&route.Config{Addr: address})
	t.Cleanup(func() { route.ReCreateServer(&route.Config{}) })
	calls := 0
	result := error(nil)
	previous := controllerGeoUpdate
	controllerGeoUpdate = func() error { calls++; return result }
	t.Cleanup(func() { controllerGeoUpdate = previous })

	post := func(path string) int {
		t.Helper()
		deadline := time.Now().Add(3 * time.Second)
		for {
			response, err := http.Post("http://"+address+path, "application/json", nil)
			if err == nil {
				_ = response.Body.Close()
				return response.StatusCode
			}
			if time.Now().After(deadline) {
				t.Fatalf("the controller never came up: %v", err)
			}
			time.Sleep(50 * time.Millisecond)
		}
	}

	for _, path := range []string{"/configs/geo", "/upgrade/geo"} {
		if status := post(path); status != http.StatusNoContent {
			t.Fatalf("POST %s = %d, want %d", path, status, http.StatusNoContent)
		}
	}
	result = errors.New("download failed")
	if status := post("/configs/geo"); status != http.StatusInternalServerError {
		t.Fatalf("a failed update answered %d, want %d", status, http.StatusInternalServerError)
	}
	if calls != 3 {
		t.Fatalf("the core's update ran %d times, want once per request", calls)
	}
}

func TestAMappedDatabaseWaitsBesideTheLoadedOneUntilTheNextStart(t *testing.T) {
	path, calls, _, reload := installedGeoFile(t)
	previous := stagesMappedFile
	t.Cleanup(func() { stagesMappedFile = previous })
	stagesMappedFile = true
	data := maxMindTestDatabase(t)

	if err := installMaxMind(data, path, reload); err != nil {
		t.Fatalf("install: %v", err)
	}
	if calls.reloaded != 0 {
		t.Fatal("reloaded the reader over a file it still maps")
	}
	if buf, _ := os.ReadFile(path); string(buf) != "old" {
		t.Fatal("replaced the database a lookup may still be reading")
	}
	if geoFileInUse(path) != pendingGeoPath(path) {
		t.Fatal("a later download would compare against the old database")
	}

	previousHome := constant.Path.HomeDir()
	constant.SetHomeDir(filepath.Dir(path))
	t.Cleanup(func() { constant.SetHomeDir(previousHome) })
	mmdbPath := constant.Path.MMDB()
	if err := os.Rename(pendingGeoPath(path), pendingGeoPath(mmdbPath)); err != nil {
		t.Fatal(err)
	}
	installPendingGeoFiles()
	if buf, _ := os.ReadFile(mmdbPath); !bytes.Equal(buf, data) || fileExists(pendingGeoPath(mmdbPath)) {
		t.Fatal("the next start left the staged database waiting")
	}
}
