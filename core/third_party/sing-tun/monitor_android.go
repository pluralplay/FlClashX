package tun

import (
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/sagernet/netlink"
)

func (m *defaultInterfaceMonitor) checkUpdate() error {
	ruleList, err := netlink.RuleList(netlink.FAMILY_ALL)
	if err != nil {
		return err
	}

	oldVPNEnabled := m.androidVPNEnabled.Load()
	var defaultTableIndex int
	var vpnEnabled bool
	for _, rule := range ruleList {
		if rule.Mask == 0x20000 {
			if rule.UIDRange == nil {
				continue
			}
			vpnEnabled = true
			if m.overrideAndroidVPN {
				defaultTableIndex = rule.Table
				break
			}
		}
		if rule.Mask == 0xFFFF {
			defaultTableIndex = rule.Table
			break
		}
	}
	m.androidVPNEnabled.Store(vpnEnabled)

	if defaultTableIndex == 0 {
		return ErrNoRoute
	}

	routes, err := netlink.RouteListFiltered(netlink.FAMILY_ALL, &netlink.Route{Table: defaultTableIndex}, netlink.RT_FILTER_TABLE)
	if err != nil {
		return err
	}

	if len(routes) == 0 {
		return E.Extend(ErrNoRoute, "no route in default table ", defaultTableIndex)
	}

	var link netlink.Link
	link, err = netlink.LinkByIndex(routes[0].LinkIndex)
	if err != nil {
		return err
	}

	newInterface, err := m.interfaceFinder.ByIndex(link.Attrs().Index)
	if err != nil {
		return E.Cause(err, "find updated interface: ", link.Attrs().Name)
	}
	oldInterface := m.defaultInterface.Swap(newInterface)
	if oldInterface != nil && oldInterface.Equals(*newInterface) && oldVPNEnabled == m.androidVPNEnabled.Load() {
		return nil
	}
	var flags int
	if oldVPNEnabled != m.androidVPNEnabled.Load() {
		flags = FlagAndroidVPNUpdate
	}
	m.emit(newInterface, flags)

	return nil
}
