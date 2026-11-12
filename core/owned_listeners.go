package core

import (
	"errors"
	"io"
	"net/netip"
	"runtime"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	IN "github.com/metacubex/mihomo/listener/inbound"
	"github.com/metacubex/mihomo/listener/tproxy"
	LT "github.com/metacubex/mihomo/listener/tunnel"
	"github.com/metacubex/mihomo/log"
)

// Kept here rather than in mihomo's own maps, which it fills with whatever
// its apply asked for, opened or not, on its own tunnel.
var (
	namedListeners = map[string]constant.InboundListener{}
	forwardTunnels = map[forwardTunnel]io.Closer{}
)

// mihomo's apply opens on its own tunnel any listener named unlike the open one and sets
// iptables for the ports it was handed; given what is open, it changes none of them.
func mihomoConfig(cfg *config.Config) *config.Config {
	general := *cfg.General
	ports := listener.GetPorts()
	general.Port, general.SocksPort, general.RedirPort = ports.Port, ports.SocksPort, ports.RedirPort
	general.TProxyPort, general.MixedPort = ports.TProxyPort, ports.MixedPort
	general.AllowLan, general.BindAddress = listener.AllowLan(), listener.BindAddress()
	general.ShadowSocksConfig = openedConfig(ports.ShadowSocksConfig, openedShadowSocks)
	general.VmessConfig = openedConfig(ports.VmessConfig, openedVmess)
	general.TuicServer = listener.GetTuicConf()
	general.Tun = LC.Tun{}
	if !isAndroid {
		general.Tun = listener.LastTunConf
	}
	shadow := *cfg
	shadow.General = &general
	shadow.Listeners, shadow.Tunnels = nil, nil
	shadow.IPTables = &config.IPTables{}
	return &shadow
}

func openedConfig(listening, given string) string {
	if listening == "" {
		return ""
	}
	return given
}

// The configs updateListeners opened them from; the listeners report another form.
var openedShadowSocks, openedVmess string

type forwardTunnel struct {
	network, address, target, proxy string
}

func patchNamedListeners(next map[string]constant.InboundListener) {
	for name, open := range namedListeners {
		if wanted, ok := next[name]; !ok || !open.Config().Equal(wanted.Config()) {
			_ = open.Close()
			delete(namedListeners, name)
		}
	}
	for name, wanted := range next {
		if _, ok := namedListeners[name]; ok {
			continue
		}
		if err := wanted.Listen(trafficTunnel); err != nil {
			log.Errorln("Listener %s listen err: %s", name, err.Error())
			closeFailedListener(wanted)
			continue
		}
		namedListeners[name] = wanted
	}
}

// These close only the sockets Listen got to, so closing one undoes a Listen
// that failed partway; the others would dereference what Listen never set.
func closeFailedListener(failed constant.InboundListener) {
	switch failed.(type) {
	case *IN.HTTP, *IN.Mixed, *IN.Socks, *IN.Redir, *IN.TProxy, *IN.Tunnel, *IN.Sudoku:
		_ = failed.Close()
	}
}

func closeMihomoTunnels() {
	defer func() {
		if r := recover(); r != nil {
			log.Warnln("[Tunnel] mihomo splits tunnel keys on \"/\", so it panicked closing one a controller reload opened: %v", r)
		}
	}()
	listener.PatchTunnel(nil, trafficTunnel)
}

func patchForwardTunnels(tunnels []LC.Tunnel) {
	wanted := map[forwardTunnel]bool{}
	for _, tunnel := range tunnels {
		for _, network := range tunnel.Network {
			wanted[forwardTunnel{network, tunnel.Address, tunnel.Target, tunnel.Proxy}] = true
		}
	}
	for key, open := range forwardTunnels {
		if !wanted[key] {
			_ = open.Close()
			delete(forwardTunnels, key)
		}
	}
	listenConfig := inbound.NewListenConfig()
	for key := range wanted {
		if _, ok := forwardTunnels[key]; ok {
			continue
		}
		var open io.Closer
		var err error
		if key.network == "tcp" {
			open, err = LT.New(key.address, key.target, key.proxy, listenConfig, trafficTunnel)
		} else {
			open, err = LT.NewUDP(key.address, key.target, key.proxy, listenConfig, trafficTunnel)
		}
		if err != nil {
			log.Errorln("Start tunnel %s error: %s", key.target, err.Error())
			continue
		}
		forwardTunnels[key] = open
		log.Infoln("Tunnel(%s/%s) proxy %s listening at: %s", key.network, key.target, key.proxy, key.address)
	}
}

type ipTablesRules struct {
	inboundInterface string
	bypass           []string
	tproxyPort       uint16
	dnsRedirect      bool
	dnsPort          uint16
}

// The checks mihomo's apply makes before it exits the process over them.
func ipTablesRulesOf(cfg *config.Config) (ipTablesRules, error) {
	rules := ipTablesRules{
		inboundInterface: "lo",
		bypass:           cfg.IPTables.Bypass,
		tproxyPort:       uint16(cfg.General.TProxyPort),
		dnsRedirect:      cfg.IPTables.DnsRedirect,
	}
	if cfg.General.Tun.Enable {
		return rules, errors.New("when tun is enabled, iptables cannot be set automatically")
	}
	if rules.tproxyPort == 0 {
		return rules, errors.New("tproxy-port must be greater than zero")
	}
	if rules.dnsRedirect {
		if !cfg.DNS.Enable {
			return rules, errors.New("DNS server must be enable")
		}
		dnsPort, err := netip.ParseAddrPort(cfg.DNS.Listen)
		if err != nil {
			return rules, errors.New("DNS server must be correct")
		}
		rules.dnsPort = dnsPort.Port()
	}
	if cfg.IPTables.InboundInterface != "" {
		rules.inboundInterface = cfg.IPTables.InboundInterface
	}
	return rules, nil
}

func updateIPTables(cfg *config.Config) {
	tproxy.CleanupTProxyIPTables()
	if runtime.GOOS != "linux" || cfg.IPTables == nil || !cfg.IPTables.Enable {
		return
	}
	rules, err := ipTablesRulesOf(cfg)
	if err == nil {
		err = installIPTables(rules, tproxy.SetTProxyIPTables)
	}
	if err != nil {
		logError("[IPTABLES] setting iptables failed: %s", err)
		return
	}
	log.Infoln("[IPTABLES] Setting iptables completed")
}

// A failed set records nothing for the cleanup, which would otherwise undo the mark.
func installIPTables(rules ipTablesRules, set func(string, []string, uint16, bool, uint16) error) error {
	marked := dialer.DefaultRoutingMark.CompareAndSwap(0, 2158)
	err := set(rules.inboundInterface, rules.bypass, rules.tproxyPort, rules.dnsRedirect, rules.dnsPort)
	if err != nil && marked {
		dialer.DefaultRoutingMark.CompareAndSwap(2158, 0)
	}
	return err
}
