package core

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	cryptotls "crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/ca"
	"github.com/metacubex/mihomo/config"
)

func withSkipCertVerify(t *testing.T, skip bool) {
	t.Helper()
	previous := skipCertVerify.Load()
	skipCertVerify.Store(skip)
	t.Cleanup(func() { skipCertVerify.Store(previous) })
}

func selfSignedServer(t *testing.T, body string) string {
	t.Helper()
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(server.Close)
	return server.URL
}

func TestDownloadRejectsAnUntrustedCertificateByDefault(t *testing.T) {
	_, err := downloadBytes(selfSignedServer(t, "ok"), 5*time.Second, false)

	if err == nil || providerRequestFailureReason(err) != "tls" {
		t.Fatalf("error = %v, want a tls failure", err)
	}
}

func TestDownloadAcceptsAnUntrustedCertificateWhenCheckIsOff(t *testing.T) {
	buf, err := downloadBytes(selfSignedServer(t, "ok"), 5*time.Second, true)

	if err != nil || string(buf) != "ok" {
		t.Fatalf("download = %q, %v; want the self-signed server accepted", buf, err)
	}
}

// A profile compiles its rule sets before the setup that would carry the setting.
func TestRuleSetDownloadTakesTheCertificatePolicyFromTheRequest(t *testing.T) {
	withRuleSetHome(t)
	withSkipCertVerify(t, false)
	url := selfSignedServer(t, "example.com\n")

	_, err := handleCompileRuleSet(CompileRuleSetParams{Name: "remote", URL: url})
	var methodErr *MethodError
	if !errors.As(err, &methodErr) || methodErr.Code != "request_error" {
		t.Fatalf("checked download: err = %v, want request_error", err)
	}

	params := CompileRuleSetParams{Name: "remote", URL: url, SkipCertVerify: true}
	if _, err := handleCompileRuleSet(params); err != nil {
		t.Fatalf("unchecked download before any setup: %v", err)
	}
}

func trustedCertificate(t *testing.T, name string, ips ...net.IP) cryptotls.Certificate {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber:          big.NewInt(time.Now().UnixNano()),
		Subject:               pkix.Name{CommonName: name},
		DNSNames:              []string{name},
		IPAddresses:           ips,
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	if err := ca.AddCertificate(string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(ca.ResetCertificate)
	return cryptotls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
}

func serverWith(t *testing.T, certificate cryptotls.Certificate, handler http.HandlerFunc) *httptest.Server {
	t.Helper()
	server := httptest.NewUnstartedServer(handler)
	server.TLS = &cryptotls.Config{Certificates: []cryptotls.Certificate{certificate}}
	server.StartTLS()
	t.Cleanup(server.Close)
	return server
}

// SNI carries no IP address, so the identity check needs the dialed host.
func TestAnUnverifiedDownloadChecksEachConnectionAgainstTheHostItDialed(t *testing.T) {
	loopback := net.IPv4(127, 0, 0, 1)
	elsewhere := serverWith(t, trustedCertificate(t, "other.test"), func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})
	here := serverWith(t, trustedCertificate(t, "here.test", loopback), func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, elsewhere.URL, http.StatusFound)
	})
	var warned []string
	previous := warnUntrusted
	warnUntrusted = func(host string, leaf *x509.Certificate, _ error) {
		warned = append(warned, host+" "+leaf.Subject.CommonName)
	}
	t.Cleanup(func() { warnUntrusted = previous })

	buf, err := downloadBytes(here.URL, 5*time.Second, true)

	if err != nil || string(buf) != "ok" {
		t.Fatalf("download = %q, %v; want the redirect followed", buf, err)
	}
	if len(warned) != 1 || warned[0] != "127.0.0.1 other.test" {
		t.Fatalf("warnings = %q, want one for the redirect target's certificate", warned)
	}
}

func TestUpdateConfigAppliesSkipCertVerify(t *testing.T) {
	withCurrentConfig(t, &config.Config{General: &config.General{}, Controller: &config.Controller{}})
	withSkipCertVerify(t, false)
	skip := true

	if err := updateConfig(&UpdateParams{SkipCertVerify: &skip}); err != nil {
		t.Fatalf("updateConfig error: %v", err)
	}
	if !skipCertVerify.Load() {
		t.Fatal("skip-cert-verify never reached the download policy")
	}
	if err := updateConfig(&UpdateParams{}); err != nil {
		t.Fatalf("updateConfig error: %v", err)
	}
	if !skipCertVerify.Load() {
		t.Error("an update without skip-cert-verify reset the download policy")
	}
}

type geoInstallCalls struct {
	updated   int
	installed [][]byte
}

func uncheckedGeoResource(t *testing.T, url string, current []byte) (geoResource, *geoInstallCalls) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "geoip.dat")
	if err := os.WriteFile(path, current, 0o644); err != nil {
		t.Fatal(err)
	}
	calls := &geoInstallCalls{}
	return geoResource{
		update:  func() error { calls.updated++; return nil },
		install: func(data []byte) error { calls.installed = append(calls.installed, data); return nil },
		url:     func() string { return url },
		path:    func() string { return path },
	}, calls
}

func TestGeoUpdateWithTheCheckOnRefusesAnUntrustedDownload(t *testing.T) {
	withSkipCertVerify(t, false)
	resource, calls := uncheckedGeoResource(t, selfSignedServer(t, "new"), []byte("old"))

	if err := resource.run(); err == nil {
		t.Fatal("a self-signed geo download was accepted with the certificate check on")
	}
	if calls.updated != 0 || len(calls.installed) != 0 {
		t.Fatalf("calls = %+v, want nothing updated or installed", calls)
	}
}

func TestGeoUpdateWithTheCheckOffInstallsWhatTheCoreDownloaded(t *testing.T) {
	withSkipCertVerify(t, true)
	resource, calls := uncheckedGeoResource(t, selfSignedServer(t, "new"), []byte("old"))

	if err := resource.run(); err != nil {
		t.Fatalf("run: %v", err)
	}
	if calls.updated != 0 || len(calls.installed) != 1 || !bytes.Equal(calls.installed[0], []byte("new")) {
		t.Fatalf("calls = %+v, want the self-signed download installed", calls)
	}
}

func TestGeoUpdateWithTheCheckOffSkipsAnUnchangedFile(t *testing.T) {
	withSkipCertVerify(t, true)
	resource, calls := uncheckedGeoResource(t, selfSignedServer(t, "same"), []byte("same"))

	if err := resource.run(); err != nil {
		t.Fatalf("run: %v", err)
	}
	if calls.updated != 0 || len(calls.installed) != 0 {
		t.Fatalf("calls = %+v, want nothing installed", calls)
	}
}

// Accepts TCP and never answers the ClientHello; closed reports the client hanging up.
func silentTLSServer(t *testing.T) (url string, closed <-chan struct{}) {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	hungUp := make(chan struct{})
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		_, _ = io.Copy(io.Discard, conn)
		close(hungUp)
	}()
	return "https://" + listener.Addr().String(), hungUp
}

func TestAnUnverifiedHandshakeEndsWithItsRequest(t *testing.T) {
	url, closed := silentTLSServer(t)

	if _, err := downloadBytes(url, 200*time.Millisecond, true); err == nil {
		t.Fatal("a server that never answered gave a download")
	}

	select {
	case <-closed:
	case <-time.After(2 * time.Second):
		t.Fatal("the connection outlived the request it was dialed for")
	}
}

func TestAnUnverifiedHandshakeHasItsOwnTimeout(t *testing.T) {
	previous := tlsHandshakeTimeout
	tlsHandshakeTimeout = 100 * time.Millisecond
	t.Cleanup(func() { tlsHandshakeTimeout = previous })
	url, _ := silentTLSServer(t)
	started := time.Now()

	if _, err := downloadBytes(url, 10*time.Second, true); err == nil {
		t.Fatal("a server that never answered gave a download")
	}

	if elapsed := time.Since(started); elapsed > 2*time.Second {
		t.Fatalf("the handshake took %v, want it cut off at its own timeout", elapsed)
	}
}

func TestADownloadPastTheSizeLimitIsRefused(t *testing.T) {
	previous := maxDownloadSize
	maxDownloadSize = 8
	t.Cleanup(func() { maxDownloadSize = previous })
	for name, declare := range map[string]bool{"declared": true, "chunked": false} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			if !declare {
				w.(http.Flusher).Flush()
			}
			_, _ = w.Write([]byte("0123456789"))
		}))
		t.Cleanup(server.Close)

		if _, err := downloadBytes(server.URL, 5*time.Second, true); !errors.Is(err, errDownloadTooLarge) {
			t.Errorf("%s: err = %v, want the size limit", name, err)
		}
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("01234567"))
	}))
	t.Cleanup(server.Close)
	if buf, err := downloadBytes(server.URL, 5*time.Second, true); err != nil || string(buf) != "01234567" {
		t.Errorf("a download at the limit = %q, %v, want it whole", buf, err)
	}
}
