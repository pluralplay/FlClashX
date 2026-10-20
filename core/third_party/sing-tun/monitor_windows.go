package tun

import (
	"net/netip"
	"sync"

	"github.com/metacubex/sing-tun/internal/winipcfg"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
	"github.com/metacubex/sing/common/x/list"

	"golang.org/x/sys/windows"
)

// zeroTierFakeGatewayIp from
// https://github.com/zerotier/ZeroTierOne/blob/1.8.6/osdep/WindowsEthernetTap.cpp#L994
var zeroTierFakeGatewayIp = netip.MustParseAddr("25.255.255.254")

type networkUpdateMonitor struct {
	routeListener     *winipcfg.RouteChangeCallback
	interfaceListener *winipcfg.InterfaceChangeCallback
	errorHandler      E.Handler

	access    sync.Mutex
	callbacks list.List[NetworkUpdateCallback]
	logger    logger.Logger
}

func NewNetworkUpdateMonitor(logger logger.Logger) (NetworkUpdateMonitor, error) {
	return &networkUpdateMonitor{
		logger: logger,
	}, nil
}

func (m *networkUpdateMonitor) Start() error {
	routeListener, err := winipcfg.RegisterRouteChangeCallback(func(notificationType winipcfg.MibNotificationType, route *winipcfg.MibIPforwardRow2) {
		m.emit()
	})
	if err != nil {
		return err
	}
	m.routeListener = routeListener
	interfaceListener, err := winipcfg.RegisterInterfaceChangeCallback(func(notificationType winipcfg.MibNotificationType, iface *winipcfg.MibIPInterfaceRow) {
		m.emit()
	})
	if err != nil {
		routeListener.Unregister()
		return err
	}
	m.interfaceListener = interfaceListener
	return nil
}

func (m *networkUpdateMonitor) Close() error {
	if m.routeListener != nil {
		m.routeListener.Unregister()
		m.routeListener = nil
	}
	if m.interfaceListener != nil {
		m.interfaceListener.Unregister()
		m.interfaceListener = nil
	}
	return nil
}

func (m *defaultInterfaceMonitor) checkUpdate() error {
	rows, err := winipcfg.GetIPForwardTable2(windows.AF_INET)
	if err != nil {
		return err
	}

	lowestMetric := ^uint32(0)
	alias := ""
	var index int

	for _, row := range rows {
		if row.DestinationPrefix.PrefixLength != 0 {
			continue
		}

		if row.NextHop.Addr() == zeroTierFakeGatewayIp {
			continue
		}

		ifrow, err := row.InterfaceLUID.Interface()
		if err != nil || ifrow.OperStatus != winipcfg.IfOperStatusUp {
			continue
		}

		if ifrow.Type == winipcfg.IfTypePropVirtual || ifrow.Type == winipcfg.IfTypeSoftwareLoopback {
			continue
		}

		iface, err := row.InterfaceLUID.IPInterface(windows.AF_INET)
		if err != nil {
			continue
		}

		if !iface.Connected {
			continue
		}

		metric := row.Metric + iface.Metric
		if metric < lowestMetric {
			lowestMetric = metric
			alias = ifrow.Alias()
			index = int(ifrow.InterfaceIndex)
		}
	}

	if alias == "" {
		return ErrNoRoute
	}

	newInterface, err := m.interfaceFinder.ByIndex(index)
	if err != nil {
		return E.Cause(err, "find updated interface: ", alias)
	}
	oldInterface := m.defaultInterface.Swap(newInterface)
	if oldInterface != nil && oldInterface.Equals(*newInterface) {
		return nil
	}
	m.emit(newInterface, 0)
	return nil
}
