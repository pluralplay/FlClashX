package tun

import (
	"context"
	"net/netip"
	"os"
	"runtime"
	"sort"
	"strconv"

	"github.com/metacubex/sing/common"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/ranges"

	"go4.org/netipx"
)

const (
	androidUserRange        = 100000
	userEnd          uint32 = 0xFFFFFFFF - 1
)

func (o *Options) BuildAndroidRules(packageManager PackageManager, errorHandler E.Handler) {
	var includeUser []uint32
	if len(o.IncludeAndroidUser) > 0 {
		o.IncludeAndroidUser = common.Uniq(o.IncludeAndroidUser)
		sort.Ints(o.IncludeAndroidUser)
		var userExcludeRange []ranges.Range[uint32]
		for _, androidUser := range o.IncludeAndroidUser {
			includeUser = append(includeUser, uint32(androidUser))
			userExcludeRange = append(userExcludeRange, ranges.New[uint32](uint32(androidUser)*androidUserRange, uint32(androidUser+1)*androidUserRange-1))
		}
		userExcludeRange = ranges.Revert(0, userEnd, userExcludeRange)
		o.ExcludeUID = append(o.ExcludeUID, userExcludeRange...)
	}
	if len(includeUser) == 0 {
		userDirs, err := os.ReadDir("/data/user")
		if err == nil {
			var userId uint64
			for _, userDir := range userDirs {
				userId, err = strconv.ParseUint(userDir.Name(), 10, 32)
				if err != nil {
					continue
				}
				includeUser = append(includeUser, uint32(userId))
			}
		}
	}
	if len(includeUser) == 0 {
		includeUser = []uint32{0}
	}
	if len(o.IncludePackage) > 0 {
		o.IncludePackage = common.Uniq(o.IncludePackage)
		for _, packageName := range o.IncludePackage {
			if sharedId, loaded := packageManager.IDBySharedPackage(packageName); loaded {
				for _, androidUser := range includeUser {
					o.IncludeUID = append(o.IncludeUID, ranges.NewSingle(sharedId+androidUser*androidUserRange))
				}
				continue
			}
			if userId, loaded := packageManager.IDByPackage(packageName); loaded {
				for _, androidUser := range includeUser {
					o.IncludeUID = append(o.IncludeUID, ranges.NewSingle(userId+androidUser*androidUserRange))
				}
				continue
			}
			errorHandler.NewError(context.Background(), E.New("package to include not found: ", packageName))
		}
	}
	if len(o.ExcludePackage) > 0 {
		o.ExcludePackage = common.Uniq(o.ExcludePackage)
		for _, packageName := range o.ExcludePackage {
			if sharedId, loaded := packageManager.IDBySharedPackage(packageName); loaded {
				for _, androidUser := range includeUser {
					o.ExcludeUID = append(o.ExcludeUID, ranges.NewSingle(sharedId+androidUser*androidUserRange))
				}
			}
			if userId, loaded := packageManager.IDByPackage(packageName); loaded {
				for _, androidUser := range includeUser {
					o.ExcludeUID = append(o.ExcludeUID, ranges.NewSingle(userId+androidUser*androidUserRange))
				}
				continue
			}
			errorHandler.NewError(context.Background(), E.New("package to exclude not found: ", packageName))
		}
	}
}

func (o *Options) ExcludedRanges() (uidRanges []ranges.Range[uint32]) {
	return buildExcludedRanges(o.IncludeUID, o.ExcludeUID)
}

func buildExcludedRanges(includeRanges []ranges.Range[uint32], excludeRanges []ranges.Range[uint32]) (uidRanges []ranges.Range[uint32]) {
	uidRanges = includeRanges
	if len(uidRanges) > 0 {
		uidRanges = ranges.Exclude(uidRanges, excludeRanges)
		uidRanges = ranges.Revert(0, userEnd, uidRanges)
	} else {
		uidRanges = excludeRanges
	}
	return ranges.Merge(uidRanges)
}

const autoRouteUseSubRanges = runtime.GOOS == "darwin"

func (o *Options) BuildAutoRouteRanges(underNetworkExtension bool) ([]netip.Prefix, error) {
	var routeRanges []netip.Prefix
	if o.AutoRoute && len(o.Inet4Address) > 0 {
		var inet4Ranges []netip.Prefix
		if len(o.Inet4RouteAddress) > 0 {
			inet4Ranges = o.Inet4RouteAddress
			if runtime.GOOS == "darwin" {
				for _, address := range o.Inet4Address {
					if address.Bits() < 32 {
						inet4Ranges = append(inet4Ranges, address.Masked())
					}
				}
			}
		} else if autoRouteUseSubRanges && !underNetworkExtension {
			inet4Ranges = []netip.Prefix{
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 1}), 8),
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 2}), 7),
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 4}), 6),
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 8}), 5),
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 16}), 4),
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 32}), 3),
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 64}), 2),
				netip.PrefixFrom(netip.AddrFrom4([4]byte{0: 128}), 1),
			}
		} else {
			inet4Ranges = []netip.Prefix{netip.PrefixFrom(netip.IPv4Unspecified(), 0)}
		}
		if len(o.Inet4RouteExcludeAddress) == 0 {
			routeRanges = append(routeRanges, inet4Ranges...)
		} else {
			var builder netipx.IPSetBuilder
			for _, inet4Range := range inet4Ranges {
				builder.AddPrefix(inet4Range)
			}
			for _, prefix := range o.Inet4RouteExcludeAddress {
				builder.RemovePrefix(prefix)
			}
			resultSet, err := builder.IPSet()
			if err != nil {
				return nil, E.Cause(err, "build IPv4 route address")
			}
			routeRanges = append(routeRanges, resultSet.Prefixes()...)
		}
	}
	if len(o.Inet6Address) > 0 {
		var inet6Ranges []netip.Prefix
		if len(o.Inet6RouteAddress) > 0 {
			inet6Ranges = o.Inet6RouteAddress
			if runtime.GOOS == "darwin" {
				for _, address := range o.Inet6Address {
					if address.Bits() < 32 {
						inet6Ranges = append(inet6Ranges, address.Masked())
					}
				}
			}
		} else if autoRouteUseSubRanges && !underNetworkExtension {
			inet6Ranges = []netip.Prefix{
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 1}), 8),
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 2}), 7),
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 4}), 6),
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 8}), 5),
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 16}), 4),
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 32}), 3),
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 64}), 2),
				netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 128}), 1),
			}
		} else {
			inet6Ranges = []netip.Prefix{netip.PrefixFrom(netip.IPv6Unspecified(), 0)}
		}
		if len(o.Inet6RouteExcludeAddress) == 0 {
			routeRanges = append(routeRanges, inet6Ranges...)
		} else {
			var builder netipx.IPSetBuilder
			for _, inet6Range := range inet6Ranges {
				builder.AddPrefix(inet6Range)
			}
			for _, prefix := range o.Inet6RouteExcludeAddress {
				builder.RemovePrefix(prefix)
			}
			resultSet, err := builder.IPSet()
			if err != nil {
				return nil, E.Cause(err, "build IPv6 route address")
			}
			routeRanges = append(routeRanges, resultSet.Prefixes()...)
		}
	}
	return routeRanges, nil
}
