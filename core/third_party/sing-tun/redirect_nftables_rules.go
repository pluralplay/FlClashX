//go:build linux

package tun

import (
	"net"
	"net/netip"
	_ "unsafe"

	"github.com/metacubex/nftables"
	"github.com/metacubex/nftables/binaryutil"
	"github.com/metacubex/nftables/expr"
	"github.com/metacubex/nftables/userdata"
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/ranges"

	"golang.org/x/exp/slices"
	"golang.org/x/sys/unix"
)

//go:linkname allocSetID github.com/metacubex/nftables.allocSetID
var allocSetID uint32

func init() {
	allocSetID = 6
}

func (r *autoRedirect) nftablesCreateAddressSets(
	nft *nftables.Conn, table *nftables.Table,
	update bool,
) error {
	routeAddressSet := *r.routeAddressSet
	routeExcludeAddressSet := *r.routeExcludeAddressSet
	if len(routeAddressSet) == 0 && len(routeExcludeAddressSet) == 0 {
		return nil
	}

	if len(routeAddressSet) > 0 {
		if r.enableIPv4 {
			_, err := nftablesCreateIPSet(nft, table, 1, "inet4_route_address_set", nftables.TableFamilyIPv4, routeAddressSet, nil, true, update)
			if err != nil {
				return err
			}
		}
		if r.enableIPv6 {
			_, err := nftablesCreateIPSet(nft, table, 2, "inet6_route_address_set", nftables.TableFamilyIPv6, routeAddressSet, nil, true, update)
			if err != nil {
				return err
			}
		}
	}

	if len(routeExcludeAddressSet) > 0 {
		if r.enableIPv4 {
			_, err := nftablesCreateIPSet(nft, table, 3, "inet4_route_exclude_address_set", nftables.TableFamilyIPv4, routeExcludeAddressSet, nil, false, update)
			if err != nil {
				return err
			}
		}
		if r.enableIPv6 {
			_, err := nftablesCreateIPSet(nft, table, 4, "inet6_route_exclude_address_set", nftables.TableFamilyIPv6, routeExcludeAddressSet, nil, false, update)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func (r *autoRedirect) nftablesCreateLocalAddressSets(
	nft *nftables.Conn, table *nftables.Table,
	localAddresses []netip.Prefix, lastAddresses []netip.Prefix,
) error {
	if r.enableIPv4 {
		localAddresses4 := common.Filter(localAddresses, func(it netip.Prefix) bool {
			return it.Addr().Is4()
		})
		updateAddresses4 := common.Filter(localAddresses, func(it netip.Prefix) bool {
			return it.Addr().Is4()
		})
		var update bool
		if len(lastAddresses) != 0 {
			if !slices.Equal(localAddresses4, updateAddresses4) {
				update = true
			}
		}
		if len(lastAddresses) == 0 || update {
			_, err := nftablesCreateIPSet(nft, table, 5, "inet4_local_address_set", nftables.TableFamilyIPv4, nil, localAddresses4, false, update)
			if err != nil {
				return err
			}
		}
	}
	if r.enableIPv6 {
		localAddresses6 := common.Filter(localAddresses, func(it netip.Prefix) bool {
			return it.Addr().Is6()
		})
		updateAddresses6 := common.Filter(localAddresses, func(it netip.Prefix) bool {
			return it.Addr().Is6()
		})
		var update bool
		if len(lastAddresses) != 0 {
			if !slices.Equal(localAddresses6, updateAddresses6) {
				update = true
			}
		}
		if len(lastAddresses) == 0 || update {
			_, err := nftablesCreateIPSet(nft, table, 6, "inet6_local_address_set", nftables.TableFamilyIPv6, nil, localAddresses6, false, update)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func (r *autoRedirect) nftablesCreateLoopbackAddressSets(
	nft *nftables.Conn, table *nftables.Table,
) error {
	if r.enableIPv4 && len(r.tunOptions.Inet4LoopbackAddress) > 0 {
		_, err := nftablesCreateIPConst(nft, table, 7, "inet4_local_redirect_address_set", nftables.TableFamilyIPv4, r.tunOptions.Inet4LoopbackAddress)
		if err != nil {
			return err
		}
	}
	if r.enableIPv6 && len(r.tunOptions.Inet6LoopbackAddress) > 0 {
		_, err := nftablesCreateIPConst(nft, table, 8, "inet6_local_redirect_address_set", nftables.TableFamilyIPv6, r.tunOptions.Inet6LoopbackAddress)
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *autoRedirect) nftablesCreateExcludeRules(nft *nftables.Conn, table *nftables.Table, chain *nftables.Chain) error {
	if r.tunOptions.AutoRedirectMarkMode && chain.Hooknum == nftables.ChainHookOutput {
		if chain.Type == nftables.ChainTypeRoute {
			ipProto := &nftables.Set{
				Table:     table,
				Anonymous: true,
				Constant:  true,
				KeyType:   nftables.TypeInetProto,
			}
			err := nft.AddSet(ipProto, []nftables.SetElement{
				{Key: []byte{unix.IPPROTO_UDP}},
				{Key: []byte{unix.IPPROTO_ICMP}},
				{Key: []byte{unix.IPPROTO_ICMPV6}},
			})
			if err != nil {
				return err
			}
			nft.AddRule(&nftables.Rule{
				Table: table,
				Chain: chain,
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
		}
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chain,
			Exprs: []expr.Any{
				&expr.Meta{
					Key:      expr.MetaKeyMARK,
					Register: 1,
				},
				&expr.Cmp{
					Op:       expr.CmpOpEq,
					Register: 1,
					Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectOutputMark),
				},
				&expr.Counter{},
				&expr.Verdict{
					Kind: expr.VerdictReturn,
				},
			},
		})
		if chain.Type == nftables.ChainTypeRoute {
			nft.AddRule(&nftables.Rule{
				Table: table,
				Chain: chain,
				Exprs: []expr.Any{
					&expr.Ct{
						Key:      expr.CtKeyMARK,
						Register: 1,
					},
					&expr.Cmp{
						Op:       expr.CmpOpEq,
						Register: 1,
						Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectOutputMark),
					},
					&expr.Counter{},
					&expr.Verdict{
						Kind: expr.VerdictReturn,
					},
				},
			})
		}
	}
	if chain.Hooknum == nftables.ChainHookPrerouting {
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chain,
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
		if len(r.tunOptions.IncludeInterface) > 0 {
			if len(r.tunOptions.IncludeInterface) > 1 {
				includeInterface := &nftables.Set{
					Table:        table,
					Anonymous:    true,
					Constant:     true,
					KeyType:      nftables.TypeIFName,
					KeyByteOrder: binaryutil.NativeEndian,
				}
				err := nft.AddSet(includeInterface, common.Map(r.tunOptions.IncludeInterface, func(it string) nftables.SetElement {
					return nftables.SetElement{
						Key: nftablesIfname(it),
					}
				}))
				if err != nil {
					return err
				}
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeyIIFNAME, Register: 1},
						&expr.Lookup{
							SourceRegister: 1,
							SetID:          includeInterface.ID,
							SetName:        includeInterface.Name,
							Invert:         true,
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			} else {
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeyIIFNAME, Register: 1},
						&expr.Cmp{
							Op:       expr.CmpOpNeq,
							Register: 1,
							Data:     nftablesIfname(r.tunOptions.IncludeInterface[0]),
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			}
		}

		if len(r.tunOptions.ExcludeInterface) > 0 {
			if len(r.tunOptions.ExcludeInterface) > 1 {
				excludeInterface := &nftables.Set{
					Table:        table,
					Anonymous:    true,
					Constant:     true,
					KeyType:      nftables.TypeIFName,
					KeyByteOrder: binaryutil.NativeEndian,
				}
				err := nft.AddSet(excludeInterface, common.Map(r.tunOptions.ExcludeInterface, func(it string) nftables.SetElement {
					return nftables.SetElement{
						Key: nftablesIfname(it),
					}
				}))
				if err != nil {
					return err
				}
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeyIIFNAME, Register: 1},
						&expr.Lookup{
							SourceRegister: 1,
							SetID:          excludeInterface.ID,
							SetName:        excludeInterface.Name,
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			} else {
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeyIIFNAME, Register: 1},
						&expr.Cmp{
							Op:       expr.CmpOpEq,
							Register: 1,
							Data:     nftablesIfname(r.tunOptions.ExcludeInterface[0]),
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			}
		}
		if len(r.tunOptions.IncludeMACAddress) > 0 {
			nft.AddRule(&nftables.Rule{
				Table: table,
				Chain: chain,
				Exprs: []expr.Any{
					&expr.Meta{Key: expr.MetaKeyIIFTYPE, Register: 1},
					&expr.Cmp{
						Op:       expr.CmpOpNeq,
						Register: 1,
						Data:     binaryutil.NativeEndian.PutUint16(unix.ARPHRD_ETHER),
					},
					&expr.Counter{},
					&expr.Verdict{
						Kind: expr.VerdictReturn,
					},
				},
			})
			if len(r.tunOptions.IncludeMACAddress) > 1 {
				includeMACSet := &nftables.Set{
					Table:     table,
					Anonymous: true,
					Constant:  true,
					KeyType:   nftables.TypeEtherAddr,
				}
				err := nft.AddSet(includeMACSet, common.Map(r.tunOptions.IncludeMACAddress, func(it net.HardwareAddr) nftables.SetElement {
					return nftables.SetElement{
						Key: []byte(it),
					}
				}))
				if err != nil {
					return err
				}
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Payload{
							OperationType: expr.PayloadLoad,
							DestRegister:  1,
							Base:          expr.PayloadBaseLLHeader,
							Offset:        6,
							Len:           6,
						},
						&expr.Lookup{
							SourceRegister: 1,
							SetID:          includeMACSet.ID,
							SetName:        includeMACSet.Name,
							Invert:         true,
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			} else {
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Payload{
							OperationType: expr.PayloadLoad,
							DestRegister:  1,
							Base:          expr.PayloadBaseLLHeader,
							Offset:        6,
							Len:           6,
						},
						&expr.Cmp{
							Op:       expr.CmpOpNeq,
							Register: 1,
							Data:     []byte(r.tunOptions.IncludeMACAddress[0]),
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			}
		}
		if len(r.tunOptions.ExcludeMACAddress) > 0 {
			if len(r.tunOptions.ExcludeMACAddress) > 1 {
				excludeMACSet := &nftables.Set{
					Table:     table,
					Anonymous: true,
					Constant:  true,
					KeyType:   nftables.TypeEtherAddr,
				}
				err := nft.AddSet(excludeMACSet, common.Map(r.tunOptions.ExcludeMACAddress, func(it net.HardwareAddr) nftables.SetElement {
					return nftables.SetElement{
						Key: []byte(it),
					}
				}))
				if err != nil {
					return err
				}
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Payload{
							OperationType: expr.PayloadLoad,
							DestRegister:  1,
							Base:          expr.PayloadBaseLLHeader,
							Offset:        6,
							Len:           6,
						},
						&expr.Lookup{
							SourceRegister: 1,
							SetID:          excludeMACSet.ID,
							SetName:        excludeMACSet.Name,
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			} else {
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Payload{
							OperationType: expr.PayloadLoad,
							DestRegister:  1,
							Base:          expr.PayloadBaseLLHeader,
							Offset:        6,
							Len:           6,
						},
						&expr.Cmp{
							Op:       expr.CmpOpEq,
							Register: 1,
							Data:     []byte(r.tunOptions.ExcludeMACAddress[0]),
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			}
		}
	} else {
		if len(r.tunOptions.IncludeUID) > 0 {
			if len(r.tunOptions.IncludeUID) > 1 || r.tunOptions.IncludeUID[0].Start != r.tunOptions.IncludeUID[0].End {
				includeUID := &nftables.Set{
					Table:     table,
					Anonymous: true,
					Constant:  true,
					Interval:  true,
					KeyType:   nftables.TypeUID,
				}
				err := nft.AddSet(includeUID, common.FlatMap(r.tunOptions.IncludeUID, func(it ranges.Range[uint32]) []nftables.SetElement {
					return []nftables.SetElement{
						{
							Key: binaryutil.NativeEndian.PutUint32(it.Start),
						},
						{
							Key:         binaryutil.NativeEndian.PutUint32(it.End + 1),
							IntervalEnd: true,
						},
					}
				}))
				if err != nil {
					return err
				}
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeySKUID, Register: 1},
						&expr.Lookup{
							SourceRegister: 1,
							SetID:          includeUID.ID,
							SetName:        includeUID.Name,
							Invert:         true,
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
					UserData: userdata.AppendString(nil, userdata.TypeComment, "not a bug :("),
				})
			} else {
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeySKUID, Register: 1},
						&expr.Cmp{
							Op:       expr.CmpOpNeq,
							Register: 1,
							Data:     binaryutil.BigEndian.PutUint32(r.tunOptions.IncludeUID[0].Start),
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			}
		}

		if len(r.tunOptions.ExcludeUID) > 0 {
			if len(r.tunOptions.ExcludeUID) > 1 || r.tunOptions.ExcludeUID[0].Start != r.tunOptions.ExcludeUID[0].End {
				excludeUID := &nftables.Set{
					Table:     table,
					Anonymous: true,
					Constant:  true,
					Interval:  true,
					KeyType:   nftables.TypeUID,
				}
				err := nft.AddSet(excludeUID, common.FlatMap(r.tunOptions.ExcludeUID, func(it ranges.Range[uint32]) []nftables.SetElement {
					return []nftables.SetElement{
						{
							Key: binaryutil.NativeEndian.PutUint32(it.Start),
						},
						{
							Key:         binaryutil.NativeEndian.PutUint32(it.End + 1),
							IntervalEnd: true,
						},
					}
				}))
				if err != nil {
					return err
				}
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeySKUID, Register: 1},
						&expr.Lookup{
							SourceRegister: 1,
							SetID:          excludeUID.ID,
							SetName:        excludeUID.Name,
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
					UserData: userdata.AppendString(nil, userdata.TypeComment, "not a bug :("),
				})
			} else {
				nft.AddRule(&nftables.Rule{
					Table: table,
					Chain: chain,
					Exprs: []expr.Any{
						&expr.Meta{Key: expr.MetaKeySKUID, Register: 1},
						&expr.Cmp{
							Op:       expr.CmpOpEq,
							Register: 1,
							Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.ExcludeUID[0].Start),
						},
						&expr.Counter{},
						&expr.Verdict{
							Kind: expr.VerdictReturn,
						},
					},
				})
			}
		}
	}

	if len(r.tunOptions.Inet4RouteAddress) > 0 {
		inet4RouteAddress, err := nftablesCreateIPSet(nft, table, 0, "", nftables.TableFamilyIPv4, nil, r.tunOptions.Inet4RouteAddress, false, false)
		if err != nil {
			return err
		}
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, inet4RouteAddress.ID, inet4RouteAddress.Name, nftables.TableFamilyIPv4, true)
	}

	if len(r.tunOptions.Inet6RouteAddress) > 0 {
		inet6RouteAddress, err := nftablesCreateIPSet(nft, table, 0, "", nftables.TableFamilyIPv6, nil, r.tunOptions.Inet6RouteAddress, false, false)
		if err != nil {
			return err
		}
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, inet6RouteAddress.ID, inet6RouteAddress.Name, nftables.TableFamilyIPv6, true)
	}

	if len(r.tunOptions.Inet4RouteExcludeAddress) > 0 {
		inet4RouteExcludeAddress, err := nftablesCreateIPSet(nft, table, 0, "", nftables.TableFamilyIPv4, nil, r.tunOptions.Inet4RouteExcludeAddress, false, false)
		if err != nil {
			return err
		}
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, inet4RouteExcludeAddress.ID, inet4RouteExcludeAddress.Name, nftables.TableFamilyIPv4, false)
	}

	if len(r.tunOptions.Inet6RouteExcludeAddress) > 0 {
		inet6RouteExcludeAddress, err := nftablesCreateIPSet(nft, table, 0, "", nftables.TableFamilyIPv6, nil, r.tunOptions.Inet6RouteExcludeAddress, false, false)
		if err != nil {
			return err
		}
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, inet6RouteExcludeAddress.ID, inet6RouteExcludeAddress.Name, nftables.TableFamilyIPv6, false)
	}

	if !r.tunOptions.EXP_DisableDNSHijack && ((chain.Hooknum == nftables.ChainHookPrerouting && chain.Type == nftables.ChainTypeNAT) ||
		(r.tunOptions.AutoRedirectMarkMode && chain.Hooknum == nftables.ChainHookOutput && chain.Type == nftables.ChainTypeNAT)) {
		if r.enableIPv4 {
			err := r.nftablesCreateDNSHijackRulesForFamily(nft, table, chain, nftables.TableFamilyIPv4, 5, "inet4_local_address_set")
			if err != nil {
				return err
			}
		}
		if r.enableIPv6 {
			err := r.nftablesCreateDNSHijackRulesForFamily(nft, table, chain, nftables.TableFamilyIPv6, 6, "inet6_local_address_set")
			if err != nil {
				return err
			}
		}
	}

	if r.enableIPv4 {
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, 5, "inet4_local_address_set", nftables.TableFamilyIPv4, false)
	}
	if r.enableIPv6 {
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, 6, "inet6_local_address_set", nftables.TableFamilyIPv6, false)
	}

	routeAddressSet := *r.routeAddressSet
	routeExcludeAddressSet := *r.routeExcludeAddressSet

	if r.enableIPv4 && len(routeAddressSet) > 0 {
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, 1, "inet4_route_address_set", nftables.TableFamilyIPv4, true)
	}

	if r.enableIPv6 && len(routeAddressSet) > 0 {
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, 2, "inet6_route_address_set", nftables.TableFamilyIPv6, true)
	}

	if r.enableIPv4 && len(routeExcludeAddressSet) > 0 {
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, 3, "inet4_route_exclude_address_set", nftables.TableFamilyIPv4, false)
	}

	if r.enableIPv6 && len(routeExcludeAddressSet) > 0 {
		nftablesCreateExcludeDestinationIPSet(nft, table, chain, 4, "inet6_route_exclude_address_set", nftables.TableFamilyIPv6, false)
	}

	mptcpVerdict := expr.VerdictDrop
	if r.tunOptions.ExcludeMPTCP {
		mptcpVerdict = expr.VerdictReturn
	}
	nft.AddRule(&nftables.Rule{
		Table: table,
		Chain: chain,
		Exprs: []expr.Any{
			&expr.Meta{
				Key:      expr.MetaKeyL4PROTO,
				Register: 1,
			},
			&expr.Cmp{
				Op:       expr.CmpOpEq,
				Register: 1,
				Data:     []byte{unix.IPPROTO_TCP},
			},
			&expr.Exthdr{
				DestRegister: 1,
				Type:         30,
				Offset:       0,
				Len:          1,
				Flags:        unix.NFT_EXTHDR_F_PRESENT,
				Op:           expr.ExthdrOpTcpopt,
			},
			&expr.Cmp{
				Op:       expr.CmpOpEq,
				Register: 1,
				Data:     []byte{1},
			},
			&expr.Counter{},
			&expr.Verdict{
				Kind: mptcpVerdict,
			},
		},
	})

	return nil
}

func (r *autoRedirect) nftablesCreateMark(nft *nftables.Conn, table *nftables.Table, chain *nftables.Chain) {
	nft.AddRule(&nftables.Rule{
		Table: table,
		Chain: chain,
		Exprs: []expr.Any{
			&expr.Immediate{
				Register: 1,
				Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectInputMark),
			},
			&expr.Meta{
				Key:            expr.MetaKeyMARK,
				Register:       1,
				SourceRegister: true,
			},
			&expr.Meta{
				Key:      expr.MetaKeyMARK,
				Register: 1,
			}, // output meta mark set myMark ct mark set meta mark
			&expr.Ct{
				Key:            expr.CtKeyMARK,
				Register:       1,
				SourceRegister: true,
			},
			&expr.Counter{},
			&expr.Verdict{
				Kind: expr.VerdictReturn,
			},
		},
	})
}

func (r *autoRedirect) nftablesCreateRedirect(
	nft *nftables.Conn, table *nftables.Table, chain *nftables.Chain,
	exprs ...expr.Any,
) error {
	exprsRedirect := []expr.Any{
		&expr.Meta{
			Key:      expr.MetaKeyL4PROTO,
			Register: 1,
		},
		&expr.Cmp{
			Op:       expr.CmpOpEq,
			Register: 1,
			Data:     []byte{unix.IPPROTO_TCP},
		},
		&expr.Counter{},
		&expr.Immediate{
			Register: 1,
			Data:     binaryutil.BigEndian.PutUint16(r.redirectPort()),
		},
		&expr.Redir{
			RegisterProtoMin: 1,
			Flags:            unix.NF_NAT_RANGE_PROTO_SPECIFIED,
		},
		&expr.Verdict{
			Kind: expr.VerdictReturn,
		},
	}
	if len(r.tunOptions.Inet4LoopbackAddress) == 0 && len(r.tunOptions.Inet6LoopbackAddress) == 0 {
		if r.enableIPv4 && !r.enableIPv6 {
			exprs = append(exprs,
				&expr.Meta{
					Key:      expr.MetaKeyNFPROTO,
					Register: 1,
				},
				&expr.Cmp{
					Op:       expr.CmpOpEq,
					Register: 1,
					Data:     []byte{uint8(nftables.TableFamilyIPv4)},
				})
		} else if !r.enableIPv4 && r.enableIPv6 {
			exprs = append(exprs,
				&expr.Meta{
					Key:      expr.MetaKeyNFPROTO,
					Register: 1,
				},
				&expr.Cmp{
					Op:       expr.CmpOpEq,
					Register: 1,
					Data:     []byte{uint8(nftables.TableFamilyIPv6)},
				})
		}
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chain,
			Exprs: append(exprs, exprsRedirect...),
		})
	} else {
		if r.enableIPv4 {
			exprs4 := exprs
			if len(r.tunOptions.Inet4LoopbackAddress) > 0 {
				exprs4 = append(exprs4, nftablesCreateDestinationIPSetExprs(7, "inet4_local_redirect_address_set", nftables.TableFamilyIPv4, true)...)
			} else {
				exprs4 = append(exprs4, &expr.Meta{
					Key:      expr.MetaKeyNFPROTO,
					Register: 1,
				}, &expr.Cmp{
					Op:       expr.CmpOpEq,
					Register: 1,
					Data:     []byte{uint8(nftables.TableFamilyIPv4)},
				})
			}
			nft.AddRule(&nftables.Rule{
				Table: table,
				Chain: chain,
				Exprs: append(exprs4, exprsRedirect...),
			})
		}
		if r.enableIPv6 {
			exprs6 := exprs
			if len(r.tunOptions.Inet6LoopbackAddress) > 0 {
				exprs6 = append(exprs6, nftablesCreateDestinationIPSetExprs(8, "inet6_local_redirect_address_set", nftables.TableFamilyIPv6, true)...)
			} else {
				exprs6 = append(exprs6, &expr.Meta{
					Key:      expr.MetaKeyNFPROTO,
					Register: 1,
				}, &expr.Cmp{
					Op:       expr.CmpOpEq,
					Register: 1,
					Data:     []byte{uint8(nftables.TableFamilyIPv6)},
				})
			}
			nft.AddRule(&nftables.Rule{
				Table: table,
				Chain: chain,
				Exprs: append(exprs6, exprsRedirect...),
			})
		}
	}
	return nil
}

func (r *autoRedirect) nftablesCreateLoopbackReroute(
	nft *nftables.Conn, table *nftables.Table, chain *nftables.Chain,
) error {
	exprs := []expr.Any{
		&expr.Meta{
			Key:      expr.MetaKeyL4PROTO,
			Register: 1,
		},
		&expr.Cmp{
			Op:       expr.CmpOpEq,
			Register: 1,
			Data:     []byte{unix.IPPROTO_TCP},
		},
		&expr.Meta{
			Key:      expr.MetaKeyMARK,
			Register: 1,
		},
		&expr.Cmp{
			Op:       expr.CmpOpNeq,
			Register: 1,
			Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectInputMark),
		},
	}
	var exprs4 []expr.Any
	if r.enableIPv4 && len(r.tunOptions.Inet4LoopbackAddress) > 0 {
		exprs4 = append(exprs, nftablesCreateDestinationIPSetExprs(7, "inet4_local_redirect_address_set", nftables.TableFamilyIPv4, false)...)
	}
	var exprs6 []expr.Any
	if r.enableIPv6 && len(r.tunOptions.Inet6LoopbackAddress) > 0 {
		exprs6 = append(exprs, nftablesCreateDestinationIPSetExprs(8, "inet6_local_redirect_address_set", nftables.TableFamilyIPv6, false)...)
	}
	var exprsCreateMark []expr.Any
	if chain.Hooknum == nftables.ChainHookPrerouting {
		exprsCreateMark = []expr.Any{
			&expr.Immediate{
				Register: 1,
				Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectInputMark),
			},
			&expr.Meta{
				Key:            expr.MetaKeyMARK,
				Register:       1,
				SourceRegister: true,
			},
			&expr.Counter{},
		}
	} else {
		exprsCreateMark = []expr.Any{
			&expr.Immediate{
				Register: 1,
				Data:     binaryutil.NativeEndian.PutUint32(r.tunOptions.AutoRedirectInputMark),
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
		}
	}
	if len(exprs4) > 0 {
		exprs4 = append(exprs4, exprsCreateMark...)
	}
	if len(exprs6) > 0 {
		exprs6 = append(exprs6, exprsCreateMark...)
	}
	if len(exprs4) > 0 {
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chain,
			Exprs: exprs4,
		})
	}
	if len(exprs6) > 0 {
		nft.AddRule(&nftables.Rule{
			Table: table,
			Chain: chain,
			Exprs: exprs6,
		})
	}
	return nil
}

func (r *autoRedirect) nftablesCreateDNSHijackRulesForFamily(
	nft *nftables.Conn, table *nftables.Table, chain *nftables.Chain,
	family nftables.TableFamily, setID uint32, setName string,
) error {
	ipProto := &nftables.Set{
		Table:     table,
		Anonymous: true,
		Constant:  true,
		KeyType:   nftables.TypeInetProto,
	}
	err := nft.AddSet(ipProto, []nftables.SetElement{
		{Key: []byte{unix.IPPROTO_TCP}},
		{Key: []byte{unix.IPPROTO_UDP}},
	})
	if err != nil {
		return err
	}
	dnsServer := common.Find(r.tunOptions.DNSServers, func(it netip.Addr) bool {
		return it.Is4() == (family == nftables.TableFamilyIPv4)
	})
	if !dnsServer.IsValid() {
		if family == nftables.TableFamilyIPv4 {
			if HasNextAddress(r.tunOptions.Inet4Address[0], 1) {
				dnsServer = r.tunOptions.Inet4Address[0].Addr().Next()
			}
		} else {
			if HasNextAddress(r.tunOptions.Inet6Address[0], 1) {
				dnsServer = r.tunOptions.Inet6Address[0].Addr().Next()
			}
		}
	}
	if !dnsServer.IsValid() {
		return nil
	}
	exprs := []expr.Any{
		&expr.Meta{
			Key:      expr.MetaKeyNFPROTO,
			Register: 1,
		},
		&expr.Cmp{
			Op:       expr.CmpOpEq,
			Register: 1,
			Data:     []byte{uint8(family)},
		},
	}
	if chain.Hooknum == nftables.ChainHookOutput {
		// It looks like we can't hijack DNS requests sent to loopback.
		// https://serverfault.com/questions/363899/iptables-dnat-from-loopback
		// and tproxy is not available in output
		exprs = append(exprs,
			&expr.Meta{
				Key:      expr.MetaKeyOIFNAME,
				Register: 1,
			},
			&expr.Cmp{
				Op:       expr.CmpOpNeq,
				Register: 1,
				Data:     nftablesIfname("lo"),
			},
		)
	} else {
		if family == nftables.TableFamilyIPv4 {
			exprs = append(exprs,
				&expr.Payload{
					OperationType: expr.PayloadLoad,
					DestRegister:  1,
					Base:          expr.PayloadBaseNetworkHeader,
					Offset:        12,
					Len:           4,
				},
			)
		} else {
			exprs = append(exprs,
				&expr.Payload{
					OperationType: expr.PayloadLoad,
					DestRegister:  1,
					Base:          expr.PayloadBaseNetworkHeader,
					Offset:        8,
					Len:           16,
				},
			)
		}
		exprs = append(exprs, &expr.Lookup{
			SourceRegister: 1,
			SetID:          setID,
			SetName:        setName,
		})
	}
	exprs = append(exprs,
		&expr.Meta{
			Key:      expr.MetaKeyL4PROTO,
			Register: 1,
		},
		&expr.Lookup{
			SourceRegister: 1,
			SetID:          ipProto.ID,
			SetName:        ipProto.Name,
		},
		&expr.Payload{
			OperationType: expr.PayloadLoad,
			DestRegister:  1,
			Base:          expr.PayloadBaseTransportHeader,
			Offset:        2,
			Len:           2,
		},
		&expr.Cmp{
			Op:       expr.CmpOpEq,
			Register: 1,
			Data:     binaryutil.BigEndian.PutUint16(53),
		},
		&expr.Counter{},
		&expr.Immediate{
			Register: 1,
			Data:     dnsServer.AsSlice(),
		},
		&expr.NAT{
			Type:       expr.NATTypeDestNAT,
			Family:     uint32(family),
			RegAddrMin: 1,
		},
	)
	nft.AddRule(&nftables.Rule{
		Table: table,
		Chain: chain,
		Exprs: exprs,
	})
	return nil
}

func (r *autoRedirect) nftablesCreateUnreachable(
	nft *nftables.Conn, table *nftables.Table, chain *nftables.Chain,
) {
	if (r.enableIPv4 && r.enableIPv6) || !r.tunOptions.StrictRoute {
		return
	}
	var nfProto nftables.TableFamily
	if r.enableIPv4 {
		nfProto = nftables.TableFamilyIPv6
	} else {
		nfProto = nftables.TableFamilyIPv4
	}
	nft.AddRule(&nftables.Rule{
		Table: table,
		Chain: chain,
		Exprs: []expr.Any{
			&expr.Meta{
				Key:      expr.MetaKeyNFPROTO,
				Register: 1,
			},
			&expr.Cmp{
				Op:       expr.CmpOpEq,
				Register: 1,
				Data:     []byte{uint8(nfProto)},
			},
			&expr.Counter{},
			&expr.Reject{},
		},
	})
}
