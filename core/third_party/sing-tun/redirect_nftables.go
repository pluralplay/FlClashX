//go:build linux

package tun

import (
	"net/netip"

	"github.com/metacubex/nftables"
	"github.com/metacubex/nftables/binaryutil"
	"github.com/metacubex/nftables/expr"
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/control"

	"golang.org/x/exp/slices"
	"golang.org/x/sys/unix"
)

func (r *autoRedirect) setupNFTables() error {
	nft, err := nftables.New()
	if err != nil {
		return err
	}
	defer nft.CloseLasting()

	table := nft.AddTable(&nftables.Table{
		Name:   r.tableName,
		Family: nftables.TableFamilyINet,
	})

	err = r.nftablesCreateAddressSets(nft, table, false)
	if err != nil {
		return err
	}

	err = r.interfaceFinder.Update()
	if err != nil {
		return err
	}
	r.localAddresses = common.FlatMap(r.interfaceFinder.Interfaces(), func(it control.Interface) []netip.Prefix {
		return common.Filter(it.Addresses, func(prefix netip.Prefix) bool {
			return it.Name == "lo" || prefix.Addr().IsGlobalUnicast()
		})
	})
	err = r.nftablesCreateLocalAddressSets(nft, table, r.localAddresses, nil)
	if err != nil {
		return err
	}

	err = r.nftablesCreateLoopbackAddressSets(nft, table)
	if err != nil {
		return err
	}

	skipOutput := len(r.tunOptions.IncludeInterface) > 0 && !common.Contains(r.tunOptions.IncludeInterface, "lo") || common.Contains(r.tunOptions.ExcludeInterface, "lo")
	if !skipOutput {
		chainOutput := nft.AddChain(&nftables.Chain{
			Name:     "output",
			Table:    table,
			Hooknum:  nftables.ChainHookOutput,
			Priority: nftables.ChainPriorityMangle,
			Type:     nftables.ChainTypeNAT,
		})
		if r.tunOptions.AutoRedirectMarkMode {
			err = r.nftablesCreateExcludeRules(nft, table, chainOutput)
			if err != nil {
				return err
			}
			r.nftablesCreateUnreachable(nft, table, chainOutput)
			err = r.nftablesCreateRedirect(nft, table, chainOutput)
			if err != nil {
				return err
			}
			if len(r.tunOptions.Inet4LoopbackAddress) > 0 || len(r.tunOptions.Inet6LoopbackAddress) > 0 {
				chainOutputRoute := nft.AddChain(&nftables.Chain{
					Name:     "output_route",
					Table:    table,
					Hooknum:  nftables.ChainHookOutput,
					Priority: nftables.ChainPriorityMangle,
					Type:     nftables.ChainTypeRoute,
				})
				err = r.nftablesCreateLoopbackReroute(nft, table, chainOutputRoute)
				if err != nil {
					return err
				}
			}
			chainOutputUDP := nft.AddChain(&nftables.Chain{
				Name:     "output_udp_icmp",
				Table:    table,
				Hooknum:  nftables.ChainHookOutput,
				Priority: nftables.ChainPriorityMangle,
				Type:     nftables.ChainTypeRoute,
			})
			err = r.nftablesCreateExcludeRules(nft, table, chainOutputUDP)
			if err != nil {
				return err
			}
			r.nftablesCreateUnreachable(nft, table, chainOutputUDP)
			r.nftablesCreateMark(nft, table, chainOutputUDP)
		} else {
			err = r.nftablesCreateRedirect(nft, table, chainOutput, &expr.Meta{
				Key:      expr.MetaKeyOIFNAME,
				Register: 1,
			}, &expr.Cmp{
				Op:       expr.CmpOpEq,
				Register: 1,
				Data:     nftablesIfname(r.tunOptions.Name),
			})
			if err != nil {
				return err
			}
		}
	}

	chainPreRouting := nft.AddChain(&nftables.Chain{
		Name:     "prerouting",
		Table:    table,
		Hooknum:  nftables.ChainHookPrerouting,
		Priority: nftables.ChainPriorityRef(*nftables.ChainPriorityNATDest + 1),
		Type:     nftables.ChainTypeNAT,
	})
	err = r.nftablesCreateExcludeRules(nft, table, chainPreRouting)
	if err != nil {
		return err
	}
	r.nftablesCreateUnreachable(nft, table, chainPreRouting)
	err = r.nftablesCreateRedirect(nft, table, chainPreRouting)
	if err != nil {
		return err
	}
	if r.tunOptions.AutoRedirectMarkMode {
		r.nftablesCreateMark(nft, table, chainPreRouting)
		if len(r.tunOptions.Inet4LoopbackAddress) > 0 || len(r.tunOptions.Inet6LoopbackAddress) > 0 {
			chainPreRoutingFilter := nft.AddChain(&nftables.Chain{
				Name:     "prerouting_filter",
				Table:    table,
				Hooknum:  nftables.ChainHookPrerouting,
				Priority: nftables.ChainPriorityRef(*nftables.ChainPriorityNATDest + 1),
				Type:     nftables.ChainTypeFilter,
			})
			err = r.nftablesCreateLoopbackReroute(nft, table, chainPreRoutingFilter)
			if err != nil {
				return err
			}
		}
		chainPreRoutingUDP := nft.AddChain(&nftables.Chain{
			Name:     "prerouting_udp_icmp",
			Table:    table,
			Hooknum:  nftables.ChainHookPrerouting,
			Priority: nftables.ChainPriorityRef(*nftables.ChainPriorityNATDest + 2),
			Type:     nftables.ChainTypeFilter,
		})
		ipProto := &nftables.Set{
			Table:     table,
			Anonymous: true,
			Constant:  true,
			KeyType:   nftables.TypeInetProto,
		}
		err = nft.AddSet(ipProto, []nftables.SetElement{
			{Key: []byte{unix.IPPROTO_UDP}},
			{Key: []byte{unix.IPPROTO_ICMP}},
			{Key: []byte{unix.IPPROTO_ICMPV6}},
		})
		if err != nil {
			return err
		}
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chainPreRoutingUDP,
			Exprs: []expr.Any{
				&expr.Meta{
					Key:      expr.MetaKeyL4PROTO,
					Register: 1,
				},
				&expr.Lookup{
					SourceRegister: 1,
					SetID:          ipProto.ID,
					SetName:        ipProto.Name,
					Invert:         true,
				},
				&expr.Verdict{
					Kind: expr.VerdictReturn,
				},
			},
		})
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chainPreRoutingUDP,
			Exprs: []expr.Any{
				&expr.Meta{
					Key:      expr.MetaKeyIIFNAME,
					Register: 1,
				},
				&expr.Cmp{
					Op:       expr.CmpOpEq,
					Register: 1,
					Data:     nftablesIfname(r.tunOptions.Name),
				},
				&expr.Counter{},
				&expr.Verdict{
					Kind: expr.VerdictReturn,
				},
			},
		})
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chainPreRoutingUDP,
			Exprs: []expr.Any{
				&expr.Meta{
					Key:      expr.MetaKeyIIFNAME,
					Register: 1,
				},
				&expr.Cmp{
					Op:       expr.CmpOpNeq,
					Register: 1,
					Data:     nftablesIfname(r.tunOptions.Name),
				},
				&expr.Ct{
					Key:      expr.CtKeyMARK,
					Register: 1,
				},
				&expr.Cmp{
					Op:       expr.CmpOpEq,
					Register: 1,
					Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectInputMark),
				},
				&expr.Meta{
					Key:            expr.MetaKeyMARK,
					Register:       1,
					SourceRegister: true,
				},
				&expr.Counter{},
			},
		})
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chainPreRoutingUDP,
			Exprs: []expr.Any{
				&expr.Ct{
					Key:      expr.CtKeyMARK,
					Register: 1,
				},
				&expr.Cmp{
					Op:       expr.CmpOpNeq,
					Register: 1,
					Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectInputMark),
				},
				&expr.Immediate{
					Register: 1,
					Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectOutputMark),
				},
				&expr.Meta{
					Key:            expr.MetaKeyMARK,
					Register:       1,
					SourceRegister: true,
				},
				&expr.Meta{
					Key:      expr.MetaKeyMARK,
					Register: 1,
				},
				&expr.Ct{
					Key:            expr.CtKeyMARK,
					Register:       1,
					SourceRegister: true,
				},
				&expr.Counter{},
			},
		})
	}

	err = r.configureOpenWRTFirewall4(nft, false)
	if err != nil {
		return err
	}

	err = nft.Flush()
	if err != nil {
		return err
	}

	r.networkListener = r.networkMonitor.RegisterCallback(func() {
		err = r.nftablesUpdateLocalAddressSet()
		if err != nil {
			r.logger.Error("update local address set: ", err)
		}
	})
	return nil
}

// TODO; test is this works
func (r *autoRedirect) nftablesUpdateLocalAddressSet() error {
	newLocalAddresses := common.FlatMap(r.interfaceFinder.Interfaces(), func(it control.Interface) []netip.Prefix {
		return common.Filter(it.Addresses, func(prefix netip.Prefix) bool {
			return it.Name == "lo" || prefix.Addr().IsGlobalUnicast()
		})
	})
	if slices.Equal(newLocalAddresses, r.localAddresses) {
		return nil
	}
	nft, err := nftables.New()
	if err != nil {
		return err
	}
	defer nft.CloseLasting()
	table, err := nft.ListTableOfFamily(r.tableName, nftables.TableFamilyINet)
	if err != nil {
		return err
	}
	err = r.nftablesCreateLocalAddressSets(nft, table, newLocalAddresses, r.localAddresses)
	if err != nil {
		return err
	}
	r.localAddresses = newLocalAddresses
	return nft.Flush()
}

func (r *autoRedirect) nftablesUpdateRouteAddressSet() error {
	nft, err := nftables.New()
	if err != nil {
		return err
	}
	defer nft.CloseLasting()
	table, err := nft.ListTableOfFamily(r.tableName, nftables.TableFamilyINet)
	if err != nil {
		return err
	}
	err = r.nftablesCreateAddressSets(nft, table, true)
	if err != nil {
		return err
	}
	return nft.Flush()
}

func (r *autoRedirect) cleanupNFTables() {
	if r.networkListener != nil {
		r.networkMonitor.UnregisterCallback(r.networkListener)
	}
	nft, err := nftables.New()
	if err != nil {
		return
	}
	nft.DelTable(&nftables.Table{
		Name:   r.tableName,
		Family: nftables.TableFamilyINet,
	})
	_ = r.configureOpenWRTFirewall4(nft, true)
	_ = nft.Flush()
	_ = nft.CloseLasting()
}
