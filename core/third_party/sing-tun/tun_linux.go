package tun

import (
	"errors"
	"fmt"
	"math/rand"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"runtime"
	"sync"
	"syscall"
	"unsafe"

	"github.com/metacubex/sing-tun/internal/gtcpip/checksum"
	"github.com/metacubex/sing-tun/internal/gtcpip/header"
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/control"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/rw"
	"github.com/metacubex/sing/common/shell"
	"github.com/metacubex/sing/common/x/list"
	"github.com/sagernet/netlink"

	"golang.org/x/sys/unix"
)

var _ LinuxTUN = (*NativeTun)(nil)

type NativeTun struct {
	tunFd             int
	tunFile           *os.File
	interfaceCallback *list.Element[DefaultInterfaceUpdateCallback]
	options           Options
	ruleIndex6        []int
	readAccess        sync.Mutex
	writeAccess       sync.Mutex
	vnetHdr           bool
	writeBuffer       []byte
	gsoToWrite        []int
	tcpGROTable       *tcpGROTable
	udpGroAccess      sync.Mutex
	udpGROTable       *udpGROTable
	gro               groDisablementFlags
	txChecksumOffload bool
}

func New(options Options) (Tun, error) {
	var nativeTun *NativeTun
	if options.FileDescriptor == 0 {
		tunFd, err := open(options.Name, options.GSO)
		if err != nil {
			return nil, err
		}
		tunLink, err := netlink.LinkByName(options.Name)
		if err != nil {
			return nil, E.Errors(err, unix.Close(tunFd))
		}
		nativeTun = &NativeTun{
			tunFd:   tunFd,
			tunFile: os.NewFile(uintptr(tunFd), "tun"),
			options: options,
		}
		err = nativeTun.configure(tunLink)
		if err != nil {
			return nil, E.Errors(err, unix.Close(tunFd))
		}
	} else {
		nativeTun = &NativeTun{
			tunFd:   options.FileDescriptor,
			tunFile: os.NewFile(uintptr(options.FileDescriptor), "tun"),
			options: options,
		}
	}
	return nativeTun, nil
}

func (t *NativeTun) FrontHeadroom() int {
	if t.vnetHdr {
		return virtioNetHdrLen
	}
	return 0
}

func (t *NativeTun) Read(p []byte) (n int, err error) {
	if t.vnetHdr {
		n, err = t.tunFile.Read(t.writeBuffer)
		if err != nil {
			if errors.Is(err, syscall.EBADFD) {
				err = os.ErrClosed
			}
			return
		}
		var sizes [1]int
		n, err = handleVirtioRead(t.writeBuffer[:n], [][]byte{p}, sizes[:], 0)
		if err != nil {
			return
		}
		if n == 0 {
			return
		}
		n = sizes[0]
		return
	} else {
		return t.tunFile.Read(p)
	}
}

// handleVirtioRead splits in into bufs, leaving offset bytes at the front of
// each buffer. It mutates sizes to reflect the size of each element of bufs,
// and returns the number of packets read.
func handleVirtioRead(in []byte, bufs [][]byte, sizes []int, offset int) (int, error) {
	var hdr virtioNetHdr
	err := hdr.decode(in)
	if err != nil {
		return 0, err
	}
	in = in[virtioNetHdrLen:]

	options, err := hdr.toGSOOptions()
	if err != nil {
		return 0, err
	}

	// Don't trust HdrLen from the kernel as it can be equal to the length
	// of the entire first packet when the kernel is handling it as part of a
	// FORWARD path. Instead, parse the transport header length and add it onto
	// CsumStart, which is synonymous for IP header length.
	if options.GSOType == GSOUDPL4 {
		options.HdrLen = options.CsumStart + 8
	} else if options.GSOType != GSONone {
		if len(in) <= int(options.CsumStart+12) {
			return 0, errors.New("packet is too short")
		}

		tcpHLen := uint16(in[options.CsumStart+12] >> 4 * 4)
		if tcpHLen < 20 || tcpHLen > 60 {
			// A TCP header must be between 20 and 60 bytes in length.
			return 0, fmt.Errorf("tcp header len is invalid: %d", tcpHLen)
		}
		options.HdrLen = options.CsumStart + tcpHLen
	}

	return GSOSplit(in, options, bufs, sizes, offset)
}

func (t *NativeTun) Write(p []byte) (n int, err error) {
	if t.vnetHdr {
		_, err = t.BatchWrite([][]byte{p}, virtioNetHdrLen)
		if err != nil {
			return
		}
		n = len(p)
		return
	}
	return t.tunFile.Write(p)
}

func (t *NativeTun) BatchSize() int {
	if !t.vnetHdr {
		return 1
	}
	/* // Not works on some devices: https://github.com/SagerNet/sing-box/issues/1605
	batchSize := int(gsoMaxSize/t.options.MTU) * 2
	if batchSize > idealBatchSize {
		batchSize = idealBatchSize
	}
	return batchSize*/
	return idealBatchSize
}

func (t *NativeTun) probeTCPGRO() error {
	ipPort := netip.AddrPortFrom(t.options.Inet4Address[0].Addr(), 0)
	fingerprint := []byte("sing-tun-probe-tun-gro")
	segmentSize := len(fingerprint)
	iphLen := 20
	tcphLen := 20
	totalLen := iphLen + tcphLen + segmentSize
	bufs := make([][]byte, 2)
	for i := range bufs {
		bufs[i] = make([]byte, virtioNetHdrLen+totalLen, virtioNetHdrLen+(totalLen*2))
		ipv4H := header.IPv4(bufs[i][virtioNetHdrLen:])
		ipv4H.Encode(&header.IPv4Fields{
			SrcAddr:  ipPort.Addr(),
			DstAddr:  ipPort.Addr(),
			Protocol: unix.IPPROTO_TCP,
			// Use a zero value TTL as best effort means to reduce chance of
			// probe packet leaking further than it needs to.
			TTL:         0,
			TotalLength: uint16(totalLen),
		})
		tcpH := header.TCP(bufs[i][virtioNetHdrLen+iphLen:])
		tcpH.Encode(&header.TCPFields{
			SrcPort:    ipPort.Port(),
			DstPort:    ipPort.Port(),
			SeqNum:     1 + uint32(i*segmentSize),
			AckNum:     1,
			DataOffset: 20,
			Flags:      header.TCPFlagAck,
			WindowSize: 3000,
		})
		copy(bufs[i][virtioNetHdrLen+iphLen+tcphLen:], fingerprint)
		ipv4H.SetChecksum(^ipv4H.CalculateChecksum())
		pseudoCsum := header.PseudoHeaderChecksum(unix.IPPROTO_TCP, ipv4H.SourceAddressSlice(), ipv4H.DestinationAddressSlice(), uint16(tcphLen+segmentSize))
		pseudoCsum = checksum.Checksum(bufs[i][virtioNetHdrLen+iphLen+tcphLen:], pseudoCsum)
		tcpH.SetChecksum(^tcpH.CalculateChecksum(pseudoCsum))
	}
	_, err := t.BatchWrite(bufs, virtioNetHdrLen)
	return err
}

func (t *NativeTun) BatchRead(buffers [][]byte, offset int, readN []int) (n int, err error) {
	t.readAccess.Lock()
	defer t.readAccess.Unlock()
	n, err = t.tunFile.Read(t.writeBuffer)
	if err != nil {
		return
	}
	return handleVirtioRead(t.writeBuffer[:n], buffers, readN, offset)
}

func (t *NativeTun) BatchWrite(buffers [][]byte, offset int) (int, error) {
	t.writeAccess.Lock()
	defer func() {
		t.tcpGROTable.reset()
		t.udpGROTable.reset()
		t.writeAccess.Unlock()
	}()
	var (
		errs  error
		total int
	)
	t.gsoToWrite = t.gsoToWrite[:0]
	if t.vnetHdr {
		err := handleGRO(buffers, offset, t.tcpGROTable, t.udpGROTable, t.gro, &t.gsoToWrite)
		if err != nil {
			return 0, err
		}
		offset -= virtioNetHdrLen
	} else {
		for i := range buffers {
			t.gsoToWrite = append(t.gsoToWrite, i)
		}
	}
	for _, toWrite := range t.gsoToWrite {
		n, err := t.tunFile.Write(buffers[toWrite][offset:])
		if errors.Is(err, syscall.EBADFD) {
			return total, os.ErrClosed
		}
		if err != nil {
			errs = errors.Join(errs, err)
		} else {
			total += n
		}
	}
	return total, errs
}

var controlPath string

func init() {
	const defaultTunPath = "/dev/net/tun"
	const androidTunPath = "/dev/tun"
	if rw.IsFile(androidTunPath) {
		controlPath = androidTunPath
	} else {
		controlPath = defaultTunPath
	}
}

func open(name string, vnetHdr bool) (int, error) {
	fd, err := unix.Open(controlPath, unix.O_RDWR, 0)
	if err != nil {
		return -1, err
	}

	var ifr struct {
		name  [16]byte
		flags uint16
		_     [22]byte
	}

	copy(ifr.name[:], name)
	ifr.flags = unix.IFF_TUN | unix.IFF_NO_PI
	if vnetHdr {
		ifr.flags |= unix.IFF_VNET_HDR
	}
	_, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(fd), unix.TUNSETIFF, uintptr(unsafe.Pointer(&ifr)))
	if errno != 0 {
		unix.Close(fd)
		return -1, errno
	}

	if err = unix.SetNonblock(fd, true); err != nil {
		unix.Close(fd)
		return -1, err
	}

	return fd, nil
}

func (t *NativeTun) configure(tunLink netlink.Link) error {
	err := netlink.LinkSetMTU(tunLink, int(t.options.MTU))
	if errors.Is(err, unix.EPERM) {
		// unprivileged
		return nil
	} else if err != nil {
		return err
	}

	if len(t.options.Inet4Address) > 0 {
		for _, address := range t.options.Inet4Address {
			addr4, _ := netlink.ParseAddr(address.String())
			err = netlink.AddrAdd(tunLink, addr4)
			if err != nil && !errors.Is(err, unix.EEXIST) {
				return err
			}
		}
	}
	if len(t.options.Inet6Address) > 0 {
		for _, address := range t.options.Inet6Address {
			addr6, _ := netlink.ParseAddr(address.String())
			err = netlink.AddrAdd(tunLink, addr6)
			if err != nil && !errors.Is(err, unix.EEXIST) {
				return err
			}
		}
	}

	if t.options.GSO {
		err = t.enableGSO()
		if err != nil {
			if t.options.Logger != nil {
				t.options.Logger.Warn(err)
			}
		}
	}

	var rxChecksumOffload bool
	rxChecksumOffload, err = checkChecksumOffload(t.options.Name, unix.ETHTOOL_GRXCSUM)
	if err == nil && !rxChecksumOffload {
		_ = setChecksumOffload(t.options.Name, unix.ETHTOOL_SRXCSUM)
	}

	if t.options._TXChecksumOffload {
		var txChecksumOffload bool
		txChecksumOffload, err = checkChecksumOffload(t.options.Name, unix.ETHTOOL_GTXCSUM)
		if err != nil {
			return err
		}
		if !txChecksumOffload {
			err = setChecksumOffload(t.options.Name, unix.ETHTOOL_STXCSUM)
			if err != nil {
				return err
			}
		}
		t.txChecksumOffload = true
	}

	err = netlink.LinkSetUp(tunLink)
	if errors.Is(err, unix.EPERM) {
		// unprivileged
		return nil
	} else if err != nil {
		return err
	}

	if t.vnetHdr && len(t.options.Inet4Address) > 0 {
		err = t.probeTCPGRO()
		if err != nil {
			t.gro.disableTCPGRO()
			t.gro.disableUDPGRO()
			if t.options.Logger != nil {
				t.options.Logger.Warn(E.Cause(err, "disabled TUN TCP & UDP GRO due to GRO probe error"))
			}
		}
	}

	if t.options.IPRoute2TableIndex == 0 {
		for {
			t.options.IPRoute2TableIndex = int(rand.Uint32())
			routeList, fErr := netlink.RouteListFiltered(netlink.FAMILY_ALL, &netlink.Route{Table: t.options.IPRoute2TableIndex}, netlink.RT_FILTER_TABLE)
			if len(routeList) == 0 || fErr != nil {
				break
			}
		}
	}

	err = t.setRoute(tunLink)
	if err != nil {
		_ = t.unsetRoute0(tunLink)
		return err
	}

	err = t.unsetRules()
	if err != nil {
		return E.Cause(err, "cleanup rules")
	}
	err = t.setRules()
	if err != nil {
		_ = t.unsetRules()
		return err
	}

	t.setSearchDomainForSystemdResolved()

	if t.options.AutoRoute && runtime.GOOS == "android" {
		t.interfaceCallback = t.options.InterfaceMonitor.RegisterCallback(t.routeUpdate)
	}
	return nil
}

func (t *NativeTun) enableGSO() error {
	vnetHdrEnabled, err := checkVNETHDREnabled(t.tunFd, t.options.Name)
	if err != nil {
		return E.Cause(err, "enable offload: check IFF_VNET_HDR enabled")
	}
	if !vnetHdrEnabled {
		return E.Cause(err, "enable offload: IFF_VNET_HDR not enabled")
	}
	err = setTCPOffload(t.tunFd)
	if err != nil {
		return E.Cause(err, "enable TCP offload")
	}
	t.vnetHdr = true
	t.writeBuffer = make([]byte, virtioNetHdrLen+int(gsoMaxSize))
	t.tcpGROTable = newTCPGROTable()
	t.udpGROTable = newUDPGROTable()
	err = setUDPOffload(t.tunFd)
	if err != nil {
		t.gro.disableUDPGRO()
	}
	return nil
}

func (t *NativeTun) Close() error {
	if t.interfaceCallback != nil {
		t.options.InterfaceMonitor.UnregisterCallback(t.interfaceCallback)
	}
	t.unsetSearchDomainForSystemdResolved()
	t.unsetAddresses()
	return E.Errors(t.unsetRoute(), t.unsetRules(), common.Close(common.PtrOrNil(t.tunFile)))
}

func (t *NativeTun) TXChecksumOffload() bool {
	return t.txChecksumOffload
}

func prefixToIPNet(prefix netip.Prefix) *net.IPNet {
	return &net.IPNet{
		IP:   prefix.Addr().AsSlice(),
		Mask: net.CIDRMask(prefix.Bits(), prefix.Addr().BitLen()),
	}
}

func (t *NativeTun) routes(tunLink netlink.Link) ([]netlink.Route, error) {
	routeRanges, err := t.options.BuildAutoRouteRanges(false)
	if err != nil {
		return nil, err
	}
	// Do not create gateway on linux by default
	gateway4, gateway6 := t.options.Inet4GatewayAddr(), t.options.Inet6GatewayAddr()
	return common.Map(routeRanges, func(it netip.Prefix) netlink.Route {
		var gateway net.IP
		if it.Addr().Is4() && !gateway4.IsUnspecified() {
			gateway = gateway4.AsSlice()
		} else if it.Addr().Is6() && !gateway6.IsUnspecified() {
			gateway = gateway6.AsSlice()
		}
		return netlink.Route{
			Dst:       prefixToIPNet(it),
			Gw:        gateway,
			LinkIndex: tunLink.Attrs().Index,
			Table:     t.options.IPRoute2TableIndex,
		}
	}), nil
}

func (t *NativeTun) nextIndex6() int {
	ruleList, err := netlink.RuleList(netlink.FAMILY_V6)
	if err != nil {
		return -1
	}
	var minIndex int
	for _, rule := range ruleList {
		if rule.Priority > 0 && (minIndex == 0 || rule.Priority < minIndex) {
			minIndex = rule.Priority
		}
	}
	minIndex--
	t.ruleIndex6 = append(t.ruleIndex6, minIndex)
	return minIndex
}

func (t *NativeTun) rules() []*netlink.Rule {
	if !t.options.AutoRoute {
		if len(t.options.Inet6Address) > 0 {
			it := netlink.NewRule()
			it.Priority = t.nextIndex6()
			it.Table = t.options.IPRoute2TableIndex
			it.Family = unix.AF_INET6
			it.OifName = t.options.Name
			return []*netlink.Rule{it}
		}
		return nil
	}

	var p4, p6 bool
	var pRule int
	if len(t.options.Inet4Address) > 0 {
		p4 = true
		pRule += 1
	}
	if len(t.options.Inet6Address) > 0 {
		p6 = true
		pRule += 1
	}
	if pRule == 0 {
		return []*netlink.Rule{}
	}

	var rules []*netlink.Rule
	var it *netlink.Rule

	excludeRanges := t.options.ExcludedRanges()

	ruleStart := t.options.IPRoute2RuleIndex
	priority := ruleStart
	priority6 := priority

	if t.options.AutoRedirectMarkMode {
		if p4 {
			it = netlink.NewRule()
			it.Priority = priority
			it.Mark = t.options.AutoRedirectOutputMark
			it.MarkSet = true
			it.Goto = priority + 2
			it.Family = unix.AF_INET
			rules = append(rules, it)
			priority++

			it = netlink.NewRule()
			it.Priority = priority
			it.Mark = t.options.AutoRedirectInputMark
			it.MarkSet = true
			it.Table = t.options.IPRoute2TableIndex
			it.Family = unix.AF_INET
			rules = append(rules, it)
			priority++

			it = netlink.NewRule()
			it.Priority = priority
			it.Family = unix.AF_INET
			rules = append(rules, it)
		}
		if p6 {
			it = netlink.NewRule()
			it.Priority = priority6
			it.Mark = t.options.AutoRedirectOutputMark
			it.MarkSet = true
			it.Goto = priority6 + 2
			it.Family = unix.AF_INET6
			rules = append(rules, it)
			priority6++

			it = netlink.NewRule()
			it.Priority = priority6
			it.Mark = t.options.AutoRedirectInputMark
			it.MarkSet = true
			it.Table = t.options.IPRoute2TableIndex
			it.Family = unix.AF_INET6
			rules = append(rules, it)
			priority6++

			it = netlink.NewRule()
			it.Priority = priority6
			it.Family = unix.AF_INET6
			rules = append(rules, it)
		}
		// Fallback rules after system default rules (32766: main, 32767: default)
		// Only reached when main and default tables have no route
		if p4 {
			it = netlink.NewRule()
			it.Priority = t.options.IPRoute2AutoRedirectFallbackRuleIndex
			it.Table = t.options.IPRoute2TableIndex
			it.Family = unix.AF_INET
			rules = append(rules, it)
		}
		if p6 {
			it = netlink.NewRule()
			it.Priority = t.options.IPRoute2AutoRedirectFallbackRuleIndex
			it.Table = t.options.IPRoute2TableIndex
			it.Family = unix.AF_INET6
			rules = append(rules, it)
		}
		return rules
	}

	nopPriority := ruleStart + 10
	for _, excludePort := range t.options.ExcludeSrcPort {
		if p4 {
			it = netlink.NewRule()
			it.Priority = priority
			it.Sport = netlink.NewRulePortRange(excludePort.Start, excludePort.End)
			it.Goto = nopPriority
			it.Family = unix.AF_INET
			rules = append(rules, it)
		}
		if p6 {
			it = netlink.NewRule()
			it.Priority = priority6
			it.Sport = netlink.NewRulePortRange(excludePort.Start, excludePort.End)
			it.Goto = nopPriority
			it.Family = unix.AF_INET6
			rules = append(rules, it)
		}
	}
	for _, excludePort := range t.options.ExcludeDstPort {
		if p4 {
			it = netlink.NewRule()
			it.Priority = priority
			it.Dport = netlink.NewRulePortRange(excludePort.Start, excludePort.End)
			it.Goto = nopPriority
			it.Family = unix.AF_INET
			rules = append(rules, it)
		}
		if p6 {
			it = netlink.NewRule()
			it.Priority = priority6
			it.Dport = netlink.NewRulePortRange(excludePort.Start, excludePort.End)
			it.Goto = nopPriority
			it.Family = unix.AF_INET6
			rules = append(rules, it)
		}
	}
	for _, excludeRange := range excludeRanges {
		if p4 {
			it = netlink.NewRule()
			it.Priority = priority
			it.UIDRange = netlink.NewRuleUIDRange(excludeRange.Start, excludeRange.End)
			it.Goto = nopPriority
			it.Family = unix.AF_INET
			rules = append(rules, it)
		}
		if p6 {
			it = netlink.NewRule()
			it.Priority = priority6
			it.UIDRange = netlink.NewRuleUIDRange(excludeRange.Start, excludeRange.End)
			it.Goto = nopPriority
			it.Family = unix.AF_INET6
			rules = append(rules, it)
		}
	}
	if len(t.options.ExcludeSrcPort) > 0 || len(t.options.ExcludeDstPort) > 0 || len(excludeRanges) > 0 {
		if p4 {
			priority++
		}
		if p6 {
			priority6++
		}
	}
	if len(t.options.IncludeInterface) > 0 {
		matchPriority := priority + 2
		for _, includeInterface := range t.options.IncludeInterface {
			if p4 {
				it = netlink.NewRule()
				it.Priority = priority
				it.IifName = includeInterface
				it.Goto = matchPriority
				it.Family = unix.AF_INET
				rules = append(rules, it)
			}
			if p6 {
				it = netlink.NewRule()
				it.Priority = priority6
				it.IifName = includeInterface
				it.Goto = matchPriority
				it.Family = unix.AF_INET6
				rules = append(rules, it)
			}
		}
		if p4 {
			priority++
		}
		if p6 {
			priority6++
		}
		if p4 {
			it = netlink.NewRule()
			it.Priority = priority
			it.Family = unix.AF_INET
			it.Goto = nopPriority
			rules = append(rules, it)
			priority++

			it = netlink.NewRule()
			it.Priority = matchPriority
			it.Family = unix.AF_INET
			rules = append(rules, it)
			priority++
		}
		if p6 {
			it = netlink.NewRule()
			it.Priority = priority6
			it.Family = unix.AF_INET6
			it.Goto = nopPriority
			rules = append(rules, it)
			priority6++

			it = netlink.NewRule()
			it.Priority = matchPriority
			it.Family = unix.AF_INET6
			rules = append(rules, it)
			priority6++
		}
	} else if len(t.options.ExcludeInterface) > 0 {
		for _, excludeInterface := range t.options.ExcludeInterface {
			if p4 {
				it = netlink.NewRule()
				it.Priority = priority
				it.IifName = excludeInterface
				it.Goto = nopPriority
				it.Family = unix.AF_INET
				rules = append(rules, it)
			}
			if p6 {
				it = netlink.NewRule()
				it.Priority = priority6
				it.IifName = excludeInterface
				it.Goto = nopPriority
				it.Family = unix.AF_INET6
				rules = append(rules, it)
			}
		}

		if p4 {
			priority++
		}
		if p6 {
			priority6++
		}
	}

	if runtime.GOOS == "android" && t.options.InterfaceMonitor.AndroidVPNEnabled() {
		const protectedFromVPN = 0x20000
		if p4 {
			it = netlink.NewRule()
			if t.options.InterfaceMonitor.OverrideAndroidVPN() {
				it.Mark = protectedFromVPN
				it.MarkSet = true
			}
			it.Mask = protectedFromVPN
			it.Priority = priority
			it.Family = unix.AF_INET
			it.Goto = nopPriority
			rules = append(rules, it)
			priority++
		}
		if p6 {
			it = netlink.NewRule()
			if t.options.InterfaceMonitor.OverrideAndroidVPN() {
				it.Mark = protectedFromVPN
				it.MarkSet = true
			}
			it.Mask = protectedFromVPN
			it.Family = unix.AF_INET6
			it.Priority = priority6
			it.Goto = nopPriority
			rules = append(rules, it)
			priority6++
		}
	}

	if t.options.StrictRoute {
		if !p4 {
			it = netlink.NewRule()
			it.Priority = priority
			it.Family = unix.AF_INET
			it.Type = unix.FR_ACT_UNREACHABLE
			rules = append(rules, it)
			priority++
		}
		if !p6 {
			it = netlink.NewRule()
			it.Priority = priority6
			it.Family = unix.AF_INET6
			it.Type = unix.FR_ACT_UNREACHABLE
			rules = append(rules, it)
			priority6++
		}
	}

	if runtime.GOOS != "android" {
		if p4 {
			for _, address := range t.options.Inet4Address {
				it = netlink.NewRule()
				it.Priority = priority
				it.Dst = address.Masked()
				it.Table = t.options.IPRoute2TableIndex
				it.Family = unix.AF_INET
				rules = append(rules, it)
			}
			priority++
		}
		if p4 {
			it = netlink.NewRule()
			it.Priority = priority
			it.Invert = true
			it.Dport = netlink.NewRulePortRange(53, 53)
			it.Table = unix.RT_TABLE_MAIN
			it.SuppressPrefixlen = 0
			it.Family = unix.AF_INET
			rules = append(rules, it)
		}
		if p6 {
			it = netlink.NewRule()
			it.Priority = priority6
			it.Invert = true
			it.Dport = netlink.NewRulePortRange(53, 53)
			it.Table = unix.RT_TABLE_MAIN
			it.SuppressPrefixlen = 0
			it.Family = unix.AF_INET6
			rules = append(rules, it)
		}
	}
	if p4 {
		it = netlink.NewRule()
		it.Priority = priority
		it.IifName = t.options.Name
		it.Goto = nopPriority
		it.Family = unix.AF_INET
		rules = append(rules, it)
		priority++

		it = netlink.NewRule()
		it.Priority = priority
		it.Invert = true
		it.IifName = "lo"
		it.Table = t.options.IPRoute2TableIndex
		it.Family = unix.AF_INET
		rules = append(rules, it)

		it = netlink.NewRule()
		it.Priority = priority
		it.IifName = "lo"
		it.Src = netip.PrefixFrom(netip.IPv4Unspecified(), 32)
		it.Table = t.options.IPRoute2TableIndex
		it.Family = unix.AF_INET
		rules = append(rules, it)

		for _, address := range t.options.Inet4Address {
			it = netlink.NewRule()
			it.Priority = priority
			it.IifName = "lo"
			it.Src = address.Masked()
			it.Table = t.options.IPRoute2TableIndex
			it.Family = unix.AF_INET
			rules = append(rules, it)
		}
		// priority++
	}
	if p6 {
		it = netlink.NewRule()
		it.Priority = priority6
		it.IifName = t.options.Name
		it.Goto = nopPriority
		it.Family = unix.AF_INET6
		rules = append(rules, it)

		it = netlink.NewRule()
		it.Priority = priority6
		it.IifName = "lo"
		it.Src = netip.PrefixFrom(netip.IPv6Unspecified(), 1)
		it.Goto = nopPriority
		it.Family = unix.AF_INET6
		rules = append(rules, it)

		it = netlink.NewRule()
		it.Priority = priority6
		it.IifName = "lo"
		it.Src = netip.PrefixFrom(netip.AddrFrom16([16]byte{0: 128}), 1)
		it.Goto = nopPriority
		it.Family = unix.AF_INET6
		rules = append(rules, it)
		priority6++

		for _, address := range t.options.Inet6Address {
			it = netlink.NewRule()
			it.Priority = priority6
			it.IifName = "lo"
			it.Src = address.Masked()
			it.Table = t.options.IPRoute2TableIndex
			it.Family = unix.AF_INET6
			rules = append(rules, it)
		}
		priority6++

		it = netlink.NewRule()
		it.Priority = priority6
		it.Table = t.options.IPRoute2TableIndex
		it.Family = unix.AF_INET6
		rules = append(rules, it)
		// priority6++
	}
	if p4 {
		it = netlink.NewRule()
		it.Priority = nopPriority
		it.Family = unix.AF_INET
		rules = append(rules, it)
	}
	if p6 {
		it = netlink.NewRule()
		it.Priority = nopPriority
		it.Family = unix.AF_INET6
		rules = append(rules, it)
	}
	return rules
}

func (t *NativeTun) setRoute(tunLink netlink.Link) error {
	routes, err := t.routes(tunLink)
	if err != nil {
		return err
	}
	for i, route := range routes {
		err := netlink.RouteAdd(&route)
		if err != nil {
			return E.Cause(err, "add route ", i)
		}
	}
	return nil
}

func (t *NativeTun) setRules() error {
	for i, rule := range t.rules() {
		err := netlink.RuleAdd(rule)
		if err != nil {
			return E.Cause(err, "add rule ", i, "/", len(t.rules()))
		}
	}
	return nil
}

func (t *NativeTun) unsetRoute() error {
	if t.options.FileDescriptor > 0 {
		return nil
	}
	tunLink, err := netlink.LinkByName(t.options.Name)
	if err != nil {
		return err
	}
	return t.unsetRoute0(tunLink)
}

func (t *NativeTun) unsetRoute0(tunLink netlink.Link) error {
	if routes, err := t.routes(tunLink); err == nil {
		for _, route := range routes {
			_ = netlink.RouteDel(&route)
		}
	}
	return nil
}

func (t *NativeTun) unsetRules() error {
	if t.options.FileDescriptor > 0 {
		return nil
	}
	if len(t.ruleIndex6) > 0 {
		for _, index := range t.ruleIndex6 {
			ruleToDel := netlink.NewRule()
			ruleToDel.Family = unix.AF_INET6
			ruleToDel.Priority = index
			err := netlink.RuleDel(ruleToDel)
			if err != nil {
				return E.Cause(err, "unset rule6 ", index)
			}
		}
		t.ruleIndex6 = nil
	}
	if t.options.AutoRoute {
		ruleList, err := netlink.RuleList(netlink.FAMILY_ALL)
		if err != nil {
			return err
		}
		for _, rule := range ruleList {
			ruleStart := t.options.IPRoute2RuleIndex
			ruleEnd := ruleStart + 10
			if rule.Priority >= ruleStart && rule.Priority <= ruleEnd || (t.options.AutoRedirectMarkMode && rule.Priority == t.options.IPRoute2AutoRedirectFallbackRuleIndex) {
				ruleToDel := netlink.NewRule()
				ruleToDel.Family = rule.Family
				ruleToDel.Priority = rule.Priority
				err = netlink.RuleDel(ruleToDel)
				if err != nil {
					return E.Cause(err, "unset rule ", rule.Priority, " for ", rule.Family)
				}
			}
		}
	}
	return nil
}

func (t *NativeTun) unsetAddresses() {
	if t.options.FileDescriptor > 0 {
		return
	}
	tunLink, err := netlink.LinkByName(t.options.Name)
	if err != nil {
		return
	}
	for _, address := range t.options.Inet4Address {
		addr, _ := netlink.ParseAddr(address.String())
		_ = netlink.AddrDel(tunLink, addr)
	}
	for _, address := range t.options.Inet6Address {
		addr, _ := netlink.ParseAddr(address.String())
		_ = netlink.AddrDel(tunLink, addr)
	}
}

func (t *NativeTun) resetRules() error {
	t.unsetRules()
	return t.setRules()
}

func (t *NativeTun) routeUpdate(_ *control.Interface, flags int) {
	if flags&FlagAndroidVPNUpdate == 0 {
		return
	}
	err := t.resetRules()
	if err != nil {
		if t.options.Logger != nil {
			t.options.Logger.Error(E.Cause(err, "reset route"))
		}
	}
}

func (t *NativeTun) setSearchDomainForSystemdResolved() {
	if t.options.EXP_DisableDNSHijack {
		return
	}
	ctlPath, err := exec.LookPath("resolvectl")
	if err != nil {
		return
	}
	dnsServer := t.options.DNSServers
	if len(dnsServer) == 0 {
		if len(t.options.Inet4Address) > 0 && HasNextAddress(t.options.Inet4Address[0], 1) {
			dnsServer = append(dnsServer, t.options.Inet4Address[0].Addr().Next())
		}
		if len(t.options.Inet6Address) > 0 && HasNextAddress(t.options.Inet6Address[0], 1) {
			dnsServer = append(dnsServer, t.options.Inet6Address[0].Addr().Next())
		}
	}
	if len(dnsServer) == 0 {
		return
	}
	go func() {
		_ = shell.Exec(ctlPath, "domain", t.options.Name, "~.").Run()
		_ = shell.Exec(ctlPath, "default-route", t.options.Name, "true").Run()
		_ = shell.Exec(ctlPath, append([]string{"dns", t.options.Name}, common.Map(dnsServer, netip.Addr.String)...)...).Run()
	}()
}

func (t *NativeTun) unsetSearchDomainForSystemdResolved() {
	if t.options.EXP_DisableDNSHijack {
		return
	}
	ctlPath, err := exec.LookPath("resolvectl")
	if err != nil {
		return
	}
	_ = shell.Exec(ctlPath, "revert", t.options.Name).Run()
	if t.options.Logger != nil {
		t.options.Logger.Debug("cleaned up DNS configuration for interface: ", t.options.Name)
	}
}
