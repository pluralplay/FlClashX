//go:build linux

package tun

import (
	"net/netip"

	"github.com/metacubex/nftables"
	"github.com/metacubex/nftables/expr"
	"github.com/metacubex/sing/common"

	"go4.org/netipx"
)

func nftablesIfname(n string) []byte {
	b := make([]byte, 16)
	copy(b, n+"\x00")
	return b
}

func nftablesCreateExcludeDestinationIPSet(
	nft *nftables.Conn, table *nftables.Table, chain *nftables.Chain,
	id uint32, name string, family nftables.TableFamily, invert bool,
) {
	nft.AddRule(&nftables.Rule{
		Table: table,
		Chain: chain,
		Exprs: append(
			nftablesCreateDestinationIPSetExprs(id, name, family, invert),
			&expr.Counter{},
			&expr.Verdict{
				Kind: expr.VerdictReturn,
			},
		),
	})
}

func nftablesCreateDestinationIPSetExprs(id uint32, name string, family nftables.TableFamily, invert bool) []expr.Any {
	exprs := []expr.Any{
		&expr.Meta{
			Key:      expr.MetaKeyNFPROTO,
			Register: 1,
		},
		&expr.Cmp{
			Op:       expr.CmpOpEq,
			Register: 1,
			Data:     []byte{byte(family)},
		},
	}
	if family == nftables.TableFamilyIPv4 {
		exprs = append(exprs,
			&expr.Payload{
				OperationType: expr.PayloadLoad,
				DestRegister:  1,
				Base:          expr.PayloadBaseNetworkHeader,
				Offset:        16,
				Len:           4,
			},
		)
	} else {
		exprs = append(exprs,
			&expr.Payload{
				OperationType: expr.PayloadLoad,
				DestRegister:  1,
				Base:          expr.PayloadBaseNetworkHeader,
				Offset:        24,
				Len:           16,
			},
		)
	}
	exprs = append(exprs, &expr.Lookup{
		SourceRegister: 1,
		SetID:          id,
		SetName:        name,
		Invert:         invert,
	})
	return exprs
}

func nftablesCreateIPConst(
	nft *nftables.Conn, table *nftables.Table, id uint32, name string, family nftables.TableFamily, addressList []netip.Addr,
) (*nftables.Set, error) {
	var keyType nftables.SetDatatype
	if family == nftables.TableFamilyIPv4 {
		keyType = nftables.TypeIPAddr
	} else {
		keyType = nftables.TypeIP6Addr
	}
	mySet := &nftables.Set{
		Table:    table,
		ID:       id,
		Name:     name,
		KeyType:  keyType,
		Constant: true,
	}
	if id == 0 {
		mySet.Anonymous = true
	}
	setElements := common.Map(addressList, func(addr netip.Addr) nftables.SetElement { return nftables.SetElement{Key: addr.AsSlice()} })
	if id == 0 {
		err := nft.AddSet(mySet, setElements)
		if err != nil {
			return nil, err
		}
		return mySet, nil
	} else {
		err := nft.AddSet(mySet, nil)
		if err != nil {
			return nil, err
		}
	}
	for len(setElements) > 0 {
		toAdd := setElements
		if len(toAdd) > 1000 {
			toAdd = toAdd[:1000]
		}
		setElements = setElements[len(toAdd):]
		err := nft.SetAddElements(mySet, toAdd)
		if err != nil {
			return nil, err
		}
		err = nft.Flush()
		if err != nil {
			return nil, err
		}
	}
	return mySet, nil
}

func nftablesCreateIPSet(
	nft *nftables.Conn, table *nftables.Table,
	id uint32, name string, family nftables.TableFamily,
	setList []*netipx.IPSet, prefixList []netip.Prefix, appendDefault bool, update bool,
) (*nftables.Set, error) {
	var builder netipx.IPSetBuilder
	for _, prefix := range prefixList {
		builder.AddPrefix(prefix)
	}
	for _, set := range setList {
		builder.AddSet(set)
	}
	ipSet, err := builder.IPSet()
	if err != nil {
		return nil, err
	}
	ipRanges := ipSet.Ranges()
	setElements := make([]nftables.SetElement, 0, len(ipRanges))
	for _, rr := range ipRanges {
		if (family == nftables.TableFamilyIPv4) != rr.From().Is4() {
			continue
		}
		endAddr := rr.To().Next()
		if !endAddr.IsValid() {
			endAddr = rr.From()
		}
		setElements = append(setElements, nftables.SetElement{
			Key: rr.From().AsSlice(),
		})
		setElements = append(setElements, nftables.SetElement{
			Key:         endAddr.AsSlice(),
			IntervalEnd: true,
		})
	}
	if appendDefault && len(setElements) == 0 {
		if family == nftables.TableFamilyIPv4 {
			setElements = append(setElements, nftables.SetElement{
				Key: netip.IPv4Unspecified().AsSlice(),
			}, nftables.SetElement{
				Key:         netip.IPv4Unspecified().AsSlice(),
				IntervalEnd: true,
			})
		} else {
			setElements = append(setElements, nftables.SetElement{
				Key: netip.IPv6Unspecified().AsSlice(),
			}, nftables.SetElement{
				Key:         netip.IPv6Unspecified().AsSlice(),
				IntervalEnd: true,
			})
		}
	}
	var keyType nftables.SetDatatype
	if family == nftables.TableFamilyIPv4 {
		keyType = nftables.TypeIPAddr
	} else {
		keyType = nftables.TypeIP6Addr
	}
	mySet := &nftables.Set{
		Table:    table,
		ID:       id,
		Name:     name,
		Interval: true,
		KeyType:  keyType,
	}
	if id == 0 {
		mySet.Anonymous = true
		mySet.Constant = true
	}
	if id == 0 {
		err := nft.AddSet(mySet, setElements)
		if err != nil {
			return nil, err
		}
		return mySet, nil
	} else if update {
		nft.FlushSet(mySet)
	} else {
		err := nft.AddSet(mySet, nil)
		if err != nil {
			return nil, err
		}
	}
	for len(setElements) > 0 {
		toAdd := setElements
		if len(toAdd) > 1000 {
			toAdd = toAdd[:1000]
		}
		setElements = setElements[len(toAdd):]
		err := nft.SetAddElements(mySet, toAdd)
		if err != nil {
			return nil, err
		}
		err = nft.Flush()
		if err != nil {
			return nil, err
		}
	}
	return mySet, nil
}
