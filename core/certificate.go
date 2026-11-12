package core

import (
	"context"
	"crypto/x509"
	"errors"
	"io"
	"net"
	"sync/atomic"
	"time"

	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/component/ca"
	"github.com/metacubex/mihomo/component/dialer"
	mihomoHttp "github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/listener/inner"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/tls"
)

// The inverse of Dart's checkCertificate. mihomo's own provider fetches build
// their TLS config with no way in, so only the core's downloads honour it.
var skipCertVerify atomic.Bool

var tlsHandshakeTimeout = 10 * time.Second

// Well above the largest geo database or rule set, and short of what the
// Android process can hold: the body is read whole before it is validated.
var maxDownloadSize int64 = 128 << 20

var errDownloadTooLarge = errors.New("download exceeds the size limit")

var warnUntrusted = func(host string, leaf *x509.Certificate, err error) {
	log.Warnln("[TLS] accepting untrusted certificate %s issued by %s for %s, certificate check is off: %v", leaf.Subject, leaf.Issuer, host, err)
}

func downloadBytes(url string, timeout time.Duration, skipVerify bool) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	var resp *http.Response
	var err error
	if skipVerify {
		resp, err = getUnverified(ctx, url)
	} else {
		resp, err = mihomoHttp.HttpRequest(ctx, url, http.MethodGet, nil, nil)
	}
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, errors.New(resp.Status)
	}
	if resp.ContentLength > maxDownloadSize {
		return nil, errDownloadTooLarge
	}
	buf, err := io.ReadAll(io.LimitReader(resp.Body, maxDownloadSize+1))
	if err == nil && int64(len(buf)) > maxDownloadSize {
		return nil, errDownloadTooLarge
	}
	return buf, err
}

// mihomo's HttpRequest, but every TLS connection is checked against the host it
// dialed: a redirect changes that host, and an IP address never travels as SNI.
func getUnverified(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", mihomoHttp.UA())
	if user := req.URL.User; user != nil {
		password, _ := user.Password()
		req.SetBasicAuth(user.Username(), password)
	}
	// The transport detaches its dials from the request; the handshake must not outlive it.
	client := http.Client{Transport: &http.Transport{
		DisableKeepAlives: true,
		DialContext:       dialDownload,
		DialTLSContext: func(_ context.Context, network, address string) (net.Conn, error) {
			return dialUnverifiedTLS(ctx, network, address)
		},
	}}
	return client.Do(req)
}

func dialDownload(ctx context.Context, network, address string) (net.Conn, error) {
	if conn, err := inner.HandleTcp(inner.GetTunnel(), address, ""); err == nil {
		return conn, nil
	}
	return dialer.DialContext(ctx, network, address)
}

func dialUnverifiedTLS(ctx context.Context, network, address string) (net.Conn, error) {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	config, err := ca.GetTLSConfig(ca.Option{TLSConfig: &tls.Config{ServerName: host, InsecureSkipVerify: true}})
	if err != nil {
		return nil, err
	}
	conn, err := dialDownload(ctx, network, address)
	if err != nil {
		return nil, err
	}
	tlsConn := tls.Client(conn, config)
	handshakeCtx, cancel := context.WithTimeout(ctx, tlsHandshakeTimeout)
	defer cancel()
	if err := tlsConn.HandshakeContext(handshakeCtx); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if certs := tlsConn.ConnectionState().PeerCertificates; len(certs) > 0 {
		if err := verifyPeer(config, certs, host); err != nil {
			warnUntrusted(host, certs[0], err)
		}
	}
	return tlsConn, nil
}

func verifyPeer(config *tls.Config, certs []*x509.Certificate, host string) error {
	opts := x509.VerifyOptions{
		Roots:         config.RootCAs,
		DNSName:       host,
		Intermediates: x509.NewCertPool(),
	}
	if config.Time != nil {
		opts.CurrentTime = config.Time()
	}
	for _, cert := range certs[1:] {
		opts.Intermediates.AddCert(cert)
	}
	_, err := certs[0].Verify(opts)
	return err
}
