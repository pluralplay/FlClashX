//go:build linux

package tun

import (
	"net/netip"
	"os/exec"
	"runtime"
	"strings"

	"github.com/metacubex/sing/common"
	E "github.com/metacubex/sing/common/exceptions"
	F "github.com/metacubex/sing/common/format"
)

func (r *autoRedirect) setupIPTables() error {
	if r.enableIPv4 {
		err := r.setupIPTablesForFamily(r.iptablesPath)
		if err != nil {
			return err
		}
	}
	if r.enableIPv6 {
		err := r.setupIPTablesForFamily(r.ip6tablesPath)
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *autoRedirect) setupIPTablesForFamily(iptablesPath string) error {
	tableNameInput := r.tableName + "-input"
	tableNameForward := r.tableName + "-forward"
	tableNameOutput := r.tableName + "-output"
	tableNamePreRouteing := r.tableName + "-prerouting"
	redirectPort := r.redirectPort()
	// OUTPUT
	err := r.runShell(iptablesPath, "-t nat -N", tableNameOutput)
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-t nat -A", tableNameOutput,
		"-p tcp -o", r.tunOptions.Name,
		"-j REDIRECT --to-ports", redirectPort)
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-t nat -I OUTPUT -j", tableNameOutput)
	if err != nil {
		return err
	}
	if runtime.GOOS == "android" {
		return nil
	}
	// INPUT
	err = r.runShell(iptablesPath, "-N", tableNameInput)
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-A", tableNameInput,
		"-i", r.tunOptions.Name, "-j", "ACCEPT")
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-A", tableNameInput,
		"-o", r.tunOptions.Name, "-j", "ACCEPT")
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-I INPUT -j", tableNameInput)
	if err != nil {
		return err
	}
	// FORWARD
	err = r.runShell(iptablesPath, "-N", tableNameForward)
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-A", tableNameForward,
		"-i", r.tunOptions.Name, "-j", "ACCEPT")
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-A", tableNameForward,
		"-o", r.tunOptions.Name, "-j", "ACCEPT")
	if err != nil {
		return err
	}
	err = r.runShell(iptablesPath, "-I FORWARD -j", tableNameForward)
	if err != nil {
		return err
	}
	// PREROUTING
	err = r.runShell(iptablesPath, "-t nat -N", tableNamePreRouteing)
	if err != nil {
		return err
	}
	var (
		routeAddress        []netip.Prefix
		routeExcludeAddress []netip.Prefix
	)
	if iptablesPath == r.iptablesPath {
		routeAddress = r.tunOptions.Inet4RouteAddress
		routeExcludeAddress = r.tunOptions.Inet4RouteExcludeAddress
	} else {
		routeAddress = r.tunOptions.Inet6RouteAddress
		routeExcludeAddress = r.tunOptions.Inet6RouteExcludeAddress
	}
	if len(routeAddress) > 0 && (len(r.tunOptions.IncludeInterface) > 0 || len(r.tunOptions.IncludeUID) > 0) {
		return E.New("`*_route_address` is conflict with `include_interface` or `include_uid`")
	}
	err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
		"-i", r.tunOptions.Name, "-j RETURN")
	if err != nil {
		return err
	}
	for _, address := range routeExcludeAddress {
		err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
			"-d", address.String(), "-j RETURN")
		if err != nil {
			return err
		}
	}
	for _, name := range r.tunOptions.ExcludeInterface {
		err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
			"-i", name, "-j RETURN")
		if err != nil {
			return err
		}
	}
	for _, uid := range r.tunOptions.ExcludeUID {
		err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
			"-m owner --uid-owner", uid, "-j RETURN")
		if err != nil {
			return err
		}
	}
	if !r.tunOptions.EXP_DisableDNSHijack {
		dnsServer := common.Find(r.tunOptions.DNSServers, func(it netip.Addr) bool {
			return it.Is4() == (iptablesPath == r.iptablesPath)
		})
		if !dnsServer.IsValid() {
			if iptablesPath == r.iptablesPath {
				if HasNextAddress(r.tunOptions.Inet4Address[0], 1) {
					dnsServer = r.tunOptions.Inet4Address[0].Addr().Next()
				}
			} else {
				if HasNextAddress(r.tunOptions.Inet6Address[0], 1) {
					dnsServer = r.tunOptions.Inet6Address[0].Addr().Next()
				}
			}
		}
		if dnsServer.IsValid() {
			if len(routeAddress) > 0 {
				for _, address := range routeAddress {
					err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
						"-d", address.String(), "-p udp --dport 53 -j DNAT --to", dnsServer)
					if err != nil {
						return err
					}
				}
			} else if len(r.tunOptions.IncludeInterface) > 0 || len(r.tunOptions.IncludeUID) > 0 {
				for _, name := range r.tunOptions.IncludeInterface {
					err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
						"-i", name, "-p udp --dport 53 -j DNAT --to", dnsServer)
					if err != nil {
						return err
					}
				}
				for _, uidRange := range r.tunOptions.IncludeUID {
					for uid := uidRange.Start; uid <= uidRange.End; uid++ {
						err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
							"-m owner --uid-owner", uid, "-p udp --dport 53 -j DNAT --to", dnsServer)
						if err != nil {
							return err
						}
					}
				}
			} else {
				err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
					"-p udp --dport 53 -j DNAT --to", dnsServer)
				if err != nil {
					return err
				}
			}
		}
	}

	err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing, "-m addrtype --dst-type LOCAL -j RETURN")
	if err != nil {
		return err
	}

	if len(routeAddress) > 0 {
		for _, address := range routeAddress {
			err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
				"-d", address.String(), "-p tcp -j REDIRECT --to-ports", redirectPort)
			if err != nil {
				return err
			}
		}
	} else if len(r.tunOptions.IncludeInterface) > 0 || len(r.tunOptions.IncludeUID) > 0 {
		for _, name := range r.tunOptions.IncludeInterface {
			err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
				"-i", name, "-p tcp -j REDIRECT --to-ports", redirectPort)
			if err != nil {
				return err
			}
		}
		for _, uidRange := range r.tunOptions.IncludeUID {
			for uid := uidRange.Start; uid <= uidRange.End; uid++ {
				err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
					"-m owner --uid-owner", uid, "-p tcp -j REDIRECT --to-ports", redirectPort)
				if err != nil {
					return err
				}
			}
		}
	} else {
		err = r.runShell(iptablesPath, "-t nat -A", tableNamePreRouteing,
			"-p tcp -j REDIRECT --to-ports", redirectPort)
		if err != nil {
			return err
		}
	}
	err = r.runShell(iptablesPath, "-t nat -I PREROUTING -j", tableNamePreRouteing)
	if err != nil {
		return err
	}
	return nil
}

func (r *autoRedirect) cleanupIPTables() {
	if r.enableIPv4 {
		r.cleanupIPTablesForFamily(r.iptablesPath)
	}
	if r.enableIPv6 {
		r.cleanupIPTablesForFamily(r.ip6tablesPath)
	}
}

func (r *autoRedirect) cleanupIPTablesForFamily(iptablesPath string) {
	tableNameInput := r.tableName + "-input"
	tableNameOutput := r.tableName + "-output"
	tableNameForward := r.tableName + "-forward"
	tableNamePreRouteing := r.tableName + "-prerouting"

	_ = r.runShell(iptablesPath, "-t nat -D OUTPUT -j", tableNameOutput)
	_ = r.runShell(iptablesPath, "-t nat -F", tableNameOutput)
	_ = r.runShell(iptablesPath, "-t nat -X", tableNameOutput)
	if runtime.GOOS == "android" {
		return
	}

	_ = r.runShell(iptablesPath, "-D INPUT -j", tableNameInput)
	_ = r.runShell(iptablesPath, "-F", tableNameInput)
	_ = r.runShell(iptablesPath, "-X", tableNameInput)

	_ = r.runShell(iptablesPath, "-D FORWARD -j", tableNameForward)
	_ = r.runShell(iptablesPath, "-F", tableNameForward)
	_ = r.runShell(iptablesPath, "-X", tableNameForward)

	_ = r.runShell(iptablesPath, "-t nat -D PREROUTING -j", tableNamePreRouteing)
	_ = r.runShell(iptablesPath, "-t nat -F", tableNamePreRouteing)
	_ = r.runShell(iptablesPath, "-t nat -X", tableNamePreRouteing)
}

func (r *autoRedirect) runShell(commands ...any) error {
	commandStr := strings.Join(F.MapToString(commands), " ")
	var command *exec.Cmd
	if r.androidSu {
		command = exec.Command(r.suPath, "-c", commandStr)
	} else {
		commandArray := strings.Split(commandStr, " ")
		command = exec.Command(commandArray[0], commandArray[1:]...)
	}
	combinedOutput, err := command.CombinedOutput()
	if err != nil {
		return E.Extend(err, F.ToString(commandStr, ": ", string(combinedOutput)))
	}
	return nil
}
