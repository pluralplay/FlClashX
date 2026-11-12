# Changelog

## v0.5.0 (2026-11-12)

**Breaking Changes**

- **profiles** Custom overwrites are removed; rebuild them as custom profiles (c2f57e9)
- **settings** The DNS and NTP override toggles are removed; DNS, NTP, sniffer and TUN are set per key, and picked keys apply to every profile (c2f57e9)
- **tun** Desktop TUN settings follow the profile until you pick them; values you changed carry over (c2f57e9)
- **settings** Settings the subscription sets belong to the provider; each one can be taken over and handed back (c2f57e9)
- **settings** TLS certificates are always checked; the toggle to turn the check off is gone (bb0e6d6)

**Features**

- **core** Built on FlClash 0.9.2 with the mihomo v1.19.34 core (c2f57e9)
- **headers** Subscription headers: flclashx-view, widgets, settings, special, newdomain, service name and logo, serverinfo, buyplan, buytraffic and background (c2f57e9)
- **headers** hideip hides the outbound IP, and app.theme lets the panel set the app theme (c2f57e9)
- **headers** flclashx-override works on the profile's own GLOBAL group (c2f57e9)
- **profiles** Subscription expiry notices; the renewal button appears on its day without waiting for an update (c2f57e9)
- **profiles** External controller and Zashboard from the subscription (c2f57e9)
- **proxies** Group and server descriptions; a group's description shows in place of the node it picked (c2f57e9)
- **settings** The subscription's authentication sets the proxy account (c2f57e9)
- **profiles** App links add a profile without a confirmation and say so (c2f57e9)
- **settings** Every setting the config names (ports, mode, TUN, stack, MTU, congestion control, routes, geo and more) is locked to the provider: a closed lock marks the provider's, an open one yours (c2f57e9)
- **settings** Take any provider setting over and hand it back one at a time; settings the config leaves out stay yours (c2f57e9)
- **settings** Panel header settings apply once per subscription update or profile switch (c2f57e9)
- **settings** strict as a third process-finding mode (c2f57e9)
- **ui** iOS-style interface: stretchy stacked sheets, context menus and slide-to-pick, drag to go back, docked search and long-press reordering (c2f57e9)
- **ui** Sidebar and floating dock; bar buttons lift on hover (c2f57e9)
- **ui** Optional two-tier Liquid Glass with frosted dashboard cards, sheets and setting groups, stepping down for the session when the GPU falls behind (c2f57e9)
- **theme** Redesigned theme colors, a higher-contrast dark mode, a refreshed app icon, new glyphs, empty states and theme page (c2f57e9)
- **l10n** French, Spanish and Korean translations, seven languages in all, and a reviewed Russian translation (c2f57e9)
- **dashboard** A redesigned dashboard around the current exit, with more cards and IP quality cached for 3 days (c2f57e9)
- **dashboard** Enhanced view on new installs; movable status card and announcement (c2f57e9)
- **dashboard** Provider logo and name on one row, with the logo cached on disk (c2f57e9)
- **dashboard** Tapping the delay opens the server picker; core restart button, now on Android too (c2f57e9)
- **dashboard** Service checks through the proxy for Gosuslugi, Sberbank, VK, Yandex and Kinopoisk, and outbound IP risk kept off Cloudflare (c2f57e9)
- **proxies** Groups as cards and group tabs as chips (c2f57e9)
- **proxies** Search, mode, test all and fold all in one button group, the rest under More; expand or collapse every group at once (c2f57e9)
- **proxies** Hide timed-out nodes and search every list (c2f57e9)
- **proxies** Add proxies to local proxies; adjustable delay test timeout (c2f57e9)
- **proxies** A profile just added opens on its first group (c2f57e9)
- **profiles** Custom profiles, with include-all in custom groups (c2f57e9)
- **profiles** Profile QR codes and phone-to-TV links (c2f57e9)
- **profiles** Share link import, .mrs rule sets and more proxy fields (c2f57e9)
- **editor** Word wrap and snippets (c2f57e9)
- **config** DNS, NTP, sniffer and TUN set per key; DNS, Hosts and ports apply without a restart; optional general overrides (c2f57e9)
- **config** DNS query log; clear the DNS cache by hand or on a network change (c2f57e9)
- **views** Sortable tables for connections, requests and DNS; recent requests and live connections on one page; punycode hosts shown in Unicode (c2f57e9)
- **core** mihomo v1.19.34: Firefox 148 and Safari 26.3 TLS fingerprints, Snell v6 and several users on a Shadowsocks listener (c2f57e9)
- **core** A crashed desktop Core restarts on its own, at most twice in a row, and names the cause (c2f57e9)
- **android** A rising vibration as the app opens; holding the start/stop button for five seconds toggles the proxy under a rising vibration (c2f57e9)
- **android** Constant 120 Hz; the Core runs in its own process and restarts without restarting the app (c2f57e9)
- **android** The VPN notification shows the service or profile name, optionally with a stop button only (c2f57e9)
- **android** TUN include and exclude packages always apply and override access control; smart selection of Russian apps and a status bar in access control; TUN routes from the subscription (c2f57e9)
- **android** Launcher shortcuts and one-step on-demand access; no Firebase analytics or crash reporting (c2f57e9)
- **android** Share today's logs from the settings (c2f57e9)
- **android** Says why the VPN did not start when its permission is refused, pointing Android 17 users at the Nearby devices permission (c2f57e9)
- **desktop** The first window opens in the phone layout at the top of the screen, so it can always be moved on small screens (c2f57e9)
- **tray** Colored tray status icons with a monochrome option on macOS; tray hotkeys, nodes and a delay test (c2f57e9)
- **app** File logs and app reset; no China presets; disclaimer and About updated; README rewritten with the subscription headers documented on flclashx.app (c2f57e9)

**Bug Fixes**

- **proxies** Updating a subscription no longer switches url-test and fallback groups to a dead first node (c2f57e9)
- **proxies** A node picked while a subscription update applies is no longer lost (c2f57e9)
- **proxies** Load balancers are tested by their nodes, and groups without a URL by the app's test URL, without doubled pings (c2f57e9)
- **profiles** A profile chosen while the app is still starting is no longer ignored, and changes typed during a save are kept (c2f57e9)
- **core** Long-lived connections keep their route; traffic of a UDP session that moved routes is counted on the new route at once (c2f57e9)
- **core** A rule set or geo download past 128 MiB, a malformed .mrs file or a profile with runaway YAML aliases can no longer exhaust memory or freeze the app (c2f57e9)
- **core** Updating the GeoIP or ASN database no longer risks crashing the Core (c2f57e9)
- **backup** A damaged or oversized backup is rejected instead of restored (c2f57e9)
- **android** A VPN start from Quick Settings while the app is starting is no longer lost, and opening the app no longer reloads a running VPN (c2f57e9)
- **android** A start cancelled right before the VPN permission prompt no longer blocks later starts (c2f57e9)
- **android** A stop on an excluded Wi-Fi network keeps the VPN off after leaving it, and VPN settings changed before exiting apply to the next Quick Settings start (c2f57e9)
- **android** Per-app rules on Android 7–9 no longer apply another app's policy to a shared UDP socket (c2f57e9)
- **desktop** Making the window narrow no longer closes an open profile editor or loses its changes (c2f57e9)
- **desktop** A system proxy FlClashX did not set is left alone; it is released while the Core is down and cleared after a crashed or killed run (c2f57e9)
- **tun** A desktop TUN that fails to start is reported and turned off instead of showing as on (c2f57e9)
- **macos** TUN runs through a root-owned copy of the Core outside the app and no longer fails after the password prompt (c2f57e9)
- **macos** The menu bar popover survives a Dock reopen; logout, restart and shutdown are no longer cancelled; launch at login works on macOS 12; tray groups are capped at 100 nodes (c2f57e9)
- **linux** TUN without systemd runs through a per-user copy of the Core and no longer locks other users out; the AppImage starts again (c2f57e9)
- **windows** The Helper and client shut down fully before installing, and a stale system proxy is cleared (c2f57e9)
- **ui** Many fixes to the interface, keyboard and TV remote focus, and to keeping data through downloads, backups and header updates (c2f57e9)

**Performance**

- **editor** Smoother editing of large files; a bracket next to the cursor or thousands of same-named share links no longer stall it (c2f57e9)
- **rules** Quick Edit no longer freezes the app on very long rule lists (c2f57e9)
- **android** Smoother UI while the proxy is busy (c2f57e9)

<!-- changelog:frozen -->
<!-- Entries below predate the structured pipeline. Their wording is kept as written; only the heading and list style were normalized. -->

