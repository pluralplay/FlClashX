// Copyright (c) 2018 Samuel Melrose
// SPDX-License-Identifier: MIT
// https://github.com/iamacarpet/go-win64api/blob/ef6dbdd6db97301ae08a55eedea773476985a602/firewall.go

//go:build windows

package winfw

import (
	"fmt"
	"runtime"

	"github.com/go-ole/go-ole"
	"github.com/go-ole/go-ole/oleutil"
)

// Firewall related API constants.
const (
	NET_FW_IP_PROTOCOL_TCP    = 6
	NET_FW_IP_PROTOCOL_UDP    = 17
	NET_FW_IP_PROTOCOL_ICMPv4 = 1
	NET_FW_IP_PROTOCOL_ICMPv6 = 58
	NET_FW_IP_PROTOCOL_ANY    = 256

	NET_FW_RULE_DIR_IN  = 1
	NET_FW_RULE_DIR_OUT = 2

	NET_FW_ACTION_BLOCK = 0
	NET_FW_ACTION_ALLOW = 1

	// NET_FW_PROFILE2_CURRENT is not real API constant, just helper used in FW functions.
	// It can mean one profile or multiple (even all) profiles. It depends on which profiles
	// are currently in use. Every active interface can have it's own profile. F.e.: Public for Wifi,
	// Domain for VPN, and Private for LAN. All at the same time.
	NET_FW_PROFILE2_CURRENT = 0
	NET_FW_PROFILE2_DOMAIN  = 1
	NET_FW_PROFILE2_PRIVATE = 2
	NET_FW_PROFILE2_PUBLIC  = 4
	NET_FW_PROFILE2_ALL     = 2147483647
)

// Firewall Rule Groups
// Use this magical strings instead of group names. It will work on all language Windows versions.
// You can find more string locations here:
// https://windows10dll.nirsoft.net/firewallapi_dll.html
const (
	NET_FW_FILE_AND_PRINTER_SHARING = "@FirewallAPI.dll,-28502"
	NET_FW_REMOTE_DESKTOP           = "@FirewallAPI.dll,-28752"
)

// FWRule represents Firewall Rule.
type FWRule struct {
	Name, Description, ApplicationName, ServiceName string
	LocalPorts, RemotePorts                         string
	// LocalAddresses, RemoteAddresses are always returned with netmask, f.e.:
	//   `10.10.1.1/255.255.255.0`
	LocalAddresses, RemoteAddresses string
	// ICMPTypesAndCodes is string. You can find define multiple codes separated by ":" (colon).
	// Types are listed here:
	// https://www.iana.org/assignments/icmp-parameters/icmp-parameters.xhtml
	// So to allow ping set it to:
	//   "0"
	ICMPTypesAndCodes string
	Grouping          string
	// InterfaceTypes can be:
	//   "LAN", "Wireless", "RemoteAccess", "All"
	// You can add multiple deviding with comma:
	//   "LAN, Wireless"
	InterfaceTypes                        string
	Protocol, Direction, Action, Profiles int32
	Enabled, EdgeTraversal                bool
}

// FirewallRuleAddAdvanced allows to modify almost all available FW Rule parameters.
// You probably do not want to use this, as function allows to create any rule, even opening all ports
// in given profile. So use with caution.
func FirewallRuleAddAdvanced(rule FWRule) (bool, error) {
	return firewallRuleAdd(rule.Name, rule.Description, rule.Grouping, rule.ApplicationName, rule.ServiceName,
		rule.LocalPorts, rule.RemotePorts, rule.LocalAddresses, rule.RemoteAddresses, rule.ICMPTypesAndCodes,
		rule.Protocol, rule.Direction, rule.Action, rule.Profiles, rule.Enabled, rule.EdgeTraversal)
}

// firewallRuleAdd is universal function to add all kinds of rules.
func firewallRuleAdd(name, description, group, appPath, serviceName, ports, remotePorts, localAddresses, remoteAddresses, icmpTypes string, protocol, direction, action, profile int32, enabled, edgeTraversal bool) (bool, error) {
	if name == "" {
		return false, fmt.Errorf("empty FW Rule name, name is mandatory")
	}

	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	u, fwPolicy, err := firewallAPIInit()
	if err != nil {
		return false, err
	}
	defer firewallAPIRelease(u, fwPolicy)

	if profile == NET_FW_PROFILE2_CURRENT {
		currentProfiles, err := oleutil.GetProperty(fwPolicy, "CurrentProfileTypes")
		if err != nil {
			return false, fmt.Errorf("Failed to get CurrentProfiles: %s", err)
		}
		profile = currentProfiles.Value().(int32)
	}
	unknownRules, err := oleutil.GetProperty(fwPolicy, "Rules")
	if err != nil {
		return false, fmt.Errorf("Failed to get Rules: %s", err)
	}
	rules := unknownRules.ToIDispatch()

	if ok, err := FirewallRuleExistsByName(rules, name); err != nil {
		return false, fmt.Errorf("Error while checking rules for duplicate: %s", err)
	} else if ok {
		return false, nil
	}

	unknown2, err := oleutil.CreateObject("HNetCfg.FWRule")
	if err != nil {
		return false, fmt.Errorf("Error creating Rule object: %s", err)
	}
	defer unknown2.Release()

	fwRule, err := unknown2.QueryInterface(ole.IID_IDispatch)
	if err != nil {
		return false, fmt.Errorf("Error creating Rule object (2): %s", err)
	}
	defer fwRule.Release()

	if _, err := oleutil.PutProperty(fwRule, "Name", name); err != nil {
		return false, fmt.Errorf("Error setting property (Name) of Rule: %s", err)
	}
	if _, err := oleutil.PutProperty(fwRule, "Description", description); err != nil {
		return false, fmt.Errorf("Error setting property (Description) of Rule: %s", err)
	}
	if appPath != "" {
		if _, err := oleutil.PutProperty(fwRule, "Applicationname", appPath); err != nil {
			return false, fmt.Errorf("Error setting property (Applicationname) of Rule: %s", err)
		}
	}
	if serviceName != "" {
		if _, err := oleutil.PutProperty(fwRule, "ServiceName", serviceName); err != nil {
			return false, fmt.Errorf("Error setting property (ServiceName) of Rule: %s", err)
		}
	}
	if protocol != 0 {
		if _, err := oleutil.PutProperty(fwRule, "Protocol", protocol); err != nil {
			return false, fmt.Errorf("Error setting property (Protocol) of Rule: %s", err)
		}
	}
	if icmpTypes != "" {
		if _, err := oleutil.PutProperty(fwRule, "IcmpTypesAndCodes", icmpTypes); err != nil {
			return false, fmt.Errorf("Error setting property (IcmpTypesAndCodes) of Rule: %s", err)
		}
	}
	if ports != "" {
		if _, err := oleutil.PutProperty(fwRule, "LocalPorts", ports); err != nil {
			return false, fmt.Errorf("Error setting property (LocalPorts) of Rule: %s", err)
		}
	}
	if remotePorts != "" {
		if _, err := oleutil.PutProperty(fwRule, "RemotePorts", remotePorts); err != nil {
			return false, fmt.Errorf("Error setting property (RemotePorts) of Rule: %s", err)
		}
	}
	if localAddresses != "" {
		if _, err := oleutil.PutProperty(fwRule, "LocalAddresses", localAddresses); err != nil {
			return false, fmt.Errorf("Error setting property (LocalAddresses) of Rule: %s", err)
		}
	}
	if remoteAddresses != "" {
		if _, err := oleutil.PutProperty(fwRule, "RemoteAddresses", remoteAddresses); err != nil {
			return false, fmt.Errorf("Error setting property (RemoteAddresses) of Rule: %s", err)
		}
	}
	if direction != 0 {
		if _, err := oleutil.PutProperty(fwRule, "Direction", direction); err != nil {
			return false, fmt.Errorf("Error setting property (Direction) of Rule: %s", err)
		}
	}
	if _, err := oleutil.PutProperty(fwRule, "Enabled", enabled); err != nil {
		return false, fmt.Errorf("Error setting property (Enabled) of Rule: %s", err)
	}
	if _, err := oleutil.PutProperty(fwRule, "Grouping", group); err != nil {
		return false, fmt.Errorf("Error setting property (Grouping) of Rule: %s", err)
	}
	if _, err := oleutil.PutProperty(fwRule, "Profiles", profile); err != nil {
		return false, fmt.Errorf("Error setting property (Profiles) of Rule: %s", err)
	}
	if _, err := oleutil.PutProperty(fwRule, "Action", action); err != nil {
		return false, fmt.Errorf("Error setting property (Action) of Rule: %s", err)
	}
	if edgeTraversal {
		if _, err := oleutil.PutProperty(fwRule, "EdgeTraversal", edgeTraversal); err != nil {
			return false, fmt.Errorf("Error setting property (EdgeTraversal) of Rule: %s", err)
		}
	}

	if _, err := oleutil.CallMethod(rules, "Add", fwRule); err != nil {
		return false, fmt.Errorf("Error adding Rule: %s", err)
	}

	return true, nil
}

func FirewallRuleExistsByName(rules *ole.IDispatch, name string) (bool, error) {
	enumProperty, err := rules.GetProperty("_NewEnum")
	if err != nil {
		return false, fmt.Errorf("Failed to get enumeration property on Rules: %s", err)
	}
	defer enumProperty.Clear()

	enum, err := enumProperty.ToIUnknown().IEnumVARIANT(ole.IID_IEnumVariant)
	if err != nil {
		return false, fmt.Errorf("Failed to cast enum to correct type: %s", err)
	}
	if enum == nil {
		return false, fmt.Errorf("can't get IEnumVARIANT, enum is nil")
	}

	for itemRaw, length, err := enum.Next(1); length > 0; itemRaw, length, err = enum.Next(1) {
		if err != nil {
			return false, fmt.Errorf("Failed to seek next Rule item: %s", err)
		}

		t, err := func() (bool, error) {
			item := itemRaw.ToIDispatch()
			defer item.Release()

			if item, err := oleutil.GetProperty(item, "Name"); err != nil {
				return false, fmt.Errorf("Failed to get Property (Name) of Rule")
			} else if item.ToString() == name {
				return true, nil
			}

			return false, nil
		}()

		if err != nil {
			return false, err
		} else if t {
			return true, nil
		}
	}

	return false, nil
}

// firewallAPIInit initialize common fw api.
// then:
// dispatch firewallAPIRelease(u, fwp)
func firewallAPIInit() (*ole.IUnknown, *ole.IDispatch, error) {
	err := ole.CoInitializeEx(0, ole.COINIT_MULTITHREADED)
	if err != nil {
		return nil, nil, fmt.Errorf("Failed to initialize COM: %s", err)
	}

	unknown, err := oleutil.CreateObject("HNetCfg.FwPolicy2")
	if err != nil {
		return nil, nil, fmt.Errorf("Failed to create FwPolicy Object: %s", err)
	}

	fwPolicy, err := unknown.QueryInterface(ole.IID_IDispatch)
	if err != nil {
		unknown.Release()
		return nil, nil, fmt.Errorf("Failed to create FwPolicy Object (2): %s", err)
	}

	return unknown, fwPolicy, nil
}

// firewallAPIRelease cleans memory.
func firewallAPIRelease(u *ole.IUnknown, fwp *ole.IDispatch) {
	fwp.Release()
	u.Release()
	ole.CoUninitialize()
}
