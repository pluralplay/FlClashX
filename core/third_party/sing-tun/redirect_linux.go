package tun

import (
	"context"
	"net/netip"
	"os"
	"os/exec"
	"runtime"

	"github.com/metacubex/nftables"
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/control"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/logger"
	M "github.com/metacubex/sing/common/metadata"
	"github.com/metacubex/sing/common/x/list"

	"go4.org/netipx"
)

type autoRedirect struct {
	tunOptions             *Options
	ctx                    context.Context
	handler                Handler
	logger                 logger.Logger
	tableName              string
	networkMonitor         NetworkUpdateMonitor
	networkListener        *list.Element[NetworkUpdateCallback]
	interfaceFinder        control.InterfaceFinder
	localAddresses         []netip.Prefix
	customRedirectPortFunc func() int
	customRedirectPort     int
	redirectServer         *redirectServer
	enableIPv4             bool
	enableIPv6             bool
	iptablesPath           string
	ip6tablesPath          string
	useNFTables            bool
	androidSu              bool
	suPath                 string
	routeAddressSet        *[]*netipx.IPSet
	routeExcludeAddressSet *[]*netipx.IPSet
}

func NewAutoRedirect(options AutoRedirectOptions) (AutoRedirect, error) {
	r := &autoRedirect{
		tunOptions:             options.TunOptions,
		ctx:                    options.Context,
		handler:                options.Handler,
		logger:                 options.Logger,
		networkMonitor:         options.NetworkMonitor,
		interfaceFinder:        options.InterfaceFinder,
		tableName:              options.TableName,
		useNFTables:            runtime.GOOS != "android" && !options.DisableNFTables,
		customRedirectPortFunc: options.CustomRedirectPort,
		routeAddressSet:        options.RouteAddressSet,
		routeExcludeAddressSet: options.RouteExcludeAddressSet,
	}
	var err error
	if runtime.GOOS == "android" {
		r.enableIPv4 = true
		r.iptablesPath = "/system/bin/iptables"
		userId := os.Getuid()
		if userId != 0 {
			r.androidSu = true
			for _, suPath := range []string{
				"su",
				"/product/bin/su",
				"/system/bin/su",
			} {
				r.suPath, err = exec.LookPath(suPath)
				if err == nil {
					break
				}
			}
			if err != nil {
				return nil, E.Extend(E.Cause(err, "root permission is required for auto redirect"), os.Getenv("PATH"))
			}
		}
	} else {
		if r.useNFTables {
			err = r.initializeNFTables()
			if err != nil && err != os.ErrInvalid {
				r.useNFTables = false
				r.logger.Debug("missing nftables support: ", err)
			}
		}
		if len(r.tunOptions.Inet4Address) > 0 {
			r.enableIPv4 = true
			if !r.useNFTables {
				r.iptablesPath, err = exec.LookPath("iptables")
				if err != nil {
					return nil, E.Cause(err, "iptables is required")
				}
			}
		}
		if len(r.tunOptions.Inet6Address) > 0 {
			r.enableIPv6 = true
			if !r.useNFTables {
				r.ip6tablesPath, err = exec.LookPath("ip6tables")
				if err != nil {
					if !r.enableIPv4 {
						return nil, E.Cause(err, "ip6tables is required")
					} else {
						r.enableIPv6 = false
						r.logger.Error("device has no ip6tables nat support: ", err)
					}
				}
			}
		}
	}
	return r, nil
}

func (r *autoRedirect) Start() error {
	if r.customRedirectPortFunc != nil {
		r.customRedirectPort = r.customRedirectPortFunc()
	}
	if r.customRedirectPort == 0 {
		var listenAddr netip.Addr
		if runtime.GOOS == "android" {
			listenAddr = netip.AddrFrom4([4]byte{127, 0, 0, 1})
		} else if r.enableIPv6 {
			listenAddr = netip.IPv6Unspecified()
		} else {
			listenAddr = netip.IPv4Unspecified()
		}
		server := newRedirectServer(r.ctx, r.handler, r.logger, listenAddr)
		err := server.Start()
		if err != nil {
			return E.Cause(err, "start redirect server")
		}
		r.redirectServer = server
	}
	var err error
	if r.useNFTables {
		r.cleanupNFTables()
		err = r.setupNFTables()
	} else {
		r.cleanupIPTables()
		err = r.setupIPTables()
	}
	return err
}

func (r *autoRedirect) Close() error {
	if r.useNFTables {
		r.cleanupNFTables()
	} else {
		r.cleanupIPTables()
	}
	return common.Close(
		common.PtrOrNil(r.redirectServer),
	)
}

func (r *autoRedirect) UpdateRouteAddressSet() {
	if r.useNFTables {
		err := r.nftablesUpdateRouteAddressSet()
		if err != nil {
			r.logger.Error("update route address set: ", err)
		}
	}
}

func (r *autoRedirect) initializeNFTables() error {
	nft, err := nftables.New()
	if err != nil {
		return err
	}
	defer nft.CloseLasting()
	_, err = nft.ListTablesOfFamily(nftables.TableFamilyIPv4)
	if err != nil {
		return err
	}
	r.useNFTables = true
	return nil
}

func (r *autoRedirect) redirectPort() uint16 {
	if r.customRedirectPort > 0 {
		return uint16(r.customRedirectPort)
	}
	return M.AddrPortFromNet(r.redirectServer.listener.Addr()).Port()
}
