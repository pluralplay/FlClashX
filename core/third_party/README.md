# Patched Go modules

## sing-tun

`github.com/metacubex/sing-tun v0.4.27`, copied from the module cache, with one
change in `tun_darwin.go`: `flushDNSCache` runs `dscacheutil -flushcache` with
`go ... .Run()` instead of `.Start()`, so the finished child is reaped and the
core no longer keeps a `<defunct>` process per TUN start on macOS. Upstream
(`meta` branch, October 2026) still has the `.Start()` call.

To update: copy the new version from `$(go env GOMODCACHE)/github.com/metacubex/sing-tun@<ver>`,
re-apply the one-line change, bump the comment on the `replace` line in `../go.mod`.
