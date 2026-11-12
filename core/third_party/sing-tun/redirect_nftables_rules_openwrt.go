//go:build linux

package tun

import (
	"os"
	"os/exec"

	"github.com/metacubex/nftables"
	E "github.com/metacubex/sing/common/exceptions"
	"github.com/metacubex/sing/common/shell"
)

func (r *autoRedirect) configureOpenWRTFirewall4(nft *nftables.Conn, cleanup bool) error {
	_, err := nft.ListTableOfFamily("fw4", nftables.TableFamilyINet)
	if err != nil {
		return nil
	}
	fw4Path, err := exec.LookPath("fw4")
	if err != nil {
		return nil
	}
	rulePath := "/etc/nftables.d/0-" + r.tableName + "-auto-redirect.nft"
	if !cleanup {
		err = os.WriteFile(rulePath, []byte(`chain input {
	type filter hook input priority filter; policy accept;
	iifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
	oifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
}
chain forward {
	type filter hook forward priority filter; policy accept;
	iifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
	oifname "`+r.tunOptions.Name+`" counter accept comment "!`+r.tableName+`: Accept traffic from tun"
}
`), 0o644)
		if err != nil {
			return E.Cause(err, "write fw4 rules")
		}
	} else if _, err = os.Stat(rulePath); os.IsNotExist(err) {
		return nil
	} else {
		err = os.Remove(rulePath)
		if err != nil {
			return E.Cause(err, "clean fw4 rules")
		}
	}
	output, err := shell.Exec(fw4Path, "reload").Read()
	if err != nil {
		return E.Extend(E.Cause(err, "reload fw4 rules"), output)
	}
	return nil
}
