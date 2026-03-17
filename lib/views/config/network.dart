import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class OverrideNetworkSettingsItemNetwork extends ConsumerWidget {
  const OverrideNetworkSettingsItemNetwork({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrideNetworkSettings = ref.watch(
      appSettingProvider.select((state) => state.overrideNetworkSettings),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListItem.switchItem(
          title: Text(appLocalizations.overrideNetworkSettings),
          subtitle: Text(appLocalizations.overrideNetworkSettingsDesc),
          delegate: SwitchDelegate(
            value: overrideNetworkSettings,
            onChanged: (value) {
              ref.read(appSettingProvider.notifier).updateState(
                    (state) => state.copyWith(
                      overrideNetworkSettings: value,
                    ),
                  );
            },
          ),
        ),
        if (!overrideNetworkSettings)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLocalizations.managedByProvider,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class VPNItem extends ConsumerWidget {
  const VPNItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enable =
        ref.watch(vpnSettingProvider.select((state) => state.enable));
    return ListItem.switchItem(
      title: const Text("VPN"),
      subtitle: Text(appLocalizations.vpnEnableDesc),
      delegate: SwitchDelegate(
        value: enable,
        onChanged: (value) async {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  enable: value,
                ),
              );
        },
      ),
    );
  }
}

class TUNItem extends ConsumerWidget {
  const TUNItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enable =
        ref.watch(patchClashConfigProvider.select((state) => state.tun.enable));

    return ListItem.switchItem(
      title: Text(appLocalizations.tun),
      subtitle: Text(appLocalizations.tunDesc),
      delegate: SwitchDelegate(
        value: enable,
        onChanged: (value) async {
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith.tun(
                  enable: value,
                ),
              );
        },
      ),
    );
  }
}

class AllowBypassItem extends ConsumerWidget {
  const AllowBypassItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowBypass =
        ref.watch(vpnSettingProvider.select((state) => state.allowBypass));
    return ListItem.switchItem(
      title: Text(appLocalizations.allowBypass),
      subtitle: Text(appLocalizations.allowBypassDesc),
      delegate: SwitchDelegate(
        value: allowBypass,
        onChanged: (value) async {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  allowBypass: value,
                ),
              );
        },
      ),
    );
  }
}

class VpnSystemProxyItem extends ConsumerWidget {
  const VpnSystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemProxy =
        ref.watch(vpnSettingProvider.select((state) => state.systemProxy));
    return ListItem.switchItem(
      title: Text(appLocalizations.systemProxy),
      subtitle: Text(appLocalizations.systemProxyDesc),
      delegate: SwitchDelegate(
        value: systemProxy,
        onChanged: (value) async {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  systemProxy: value,
                ),
              );
        },
      ),
    );
  }
}

class SystemProxyItem extends ConsumerWidget {
  const SystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemProxy =
        ref.watch(networkSettingProvider.select((state) => state.systemProxy));

    return ListItem.switchItem(
      title: Text(appLocalizations.systemProxy),
      subtitle: Text(appLocalizations.systemProxyDesc),
      delegate: SwitchDelegate(
        value: systemProxy,
        onChanged: (value) async {
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  systemProxy: value,
                ),
              );
        },
      ),
    );
  }
}

class Ipv6Item extends ConsumerWidget {
  const Ipv6Item({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ipv6 = ref.watch(vpnSettingProvider.select((state) => state.ipv6));
    return ListItem.switchItem(
      title: const Text("IPv6"),
      subtitle: Text(appLocalizations.ipv6InboundDesc),
      delegate: SwitchDelegate(
        value: ipv6,
        onChanged: (value) async {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  ipv6: value,
                ),
              );
        },
      ),
    );
  }
}

class AutoSetSystemDnsItem extends ConsumerWidget {
  const AutoSetSystemDnsItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoSetSystemDns = ref.watch(
        networkSettingProvider.select((state) => state.autoSetSystemDns));
    return ListItem.switchItem(
      title: Text(appLocalizations.autoSetSystemDns),
      delegate: SwitchDelegate(
        value: autoSetSystemDns,
        onChanged: (value) async {
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  autoSetSystemDns: value,
                ),
              );
        },
      ),
    );
  }
}

class TunStackItem extends ConsumerWidget {
  const TunStackItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack =
        ref.watch(patchClashConfigProvider.select((state) => state.tun.stack));
    final overrideNetworkSettings = ref.watch(
      appSettingProvider.select((state) => state.overrideNetworkSettings),
    );
    final isEnabled = overrideNetworkSettings;
    commonPrint.log("TunStackItem.build: stack=${stack.name}, isEnabled=$isEnabled");

    return AbsorbPointer(
      absorbing: !isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: ListItem.options(
          title: Text(appLocalizations.stackMode),
          subtitle: Text(stack.name),
          delegate: OptionsDelegate<TunStack>(
            value: stack,
            options: TunStack.values,
            textBuilder: (value) => value.name,
            onChanged: (value) async {
              if (value == null) {
                return;
              }
              ref.read(patchClashConfigProvider.notifier).updateState(
                    (state) => state.copyWith.tun(
                      stack: value,
                    ),
                  );
              globalState.appController.updateClashConfigDebounce();
            },
            title: appLocalizations.stackMode,
          ),
        ),
      ),
    );
  }
}

class BypassDomainItem extends StatelessWidget {
  const BypassDomainItem({super.key});

  void _initActions(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      context.commonScaffoldState?.actions = [
        IconButton(
          onPressed: () async {
            final res = await globalState.showMessage(
              title: appLocalizations.reset,
              message: TextSpan(
                text: appLocalizations.resetTip,
              ),
            );
            if (res != true) {
              return;
            }
            ref.read(networkSettingProvider.notifier).updateState(
                  (state) => state.copyWith(
                    bypassDomain: defaultBypassDomain,
                  ),
                );
          },
          tooltip: appLocalizations.reset,
          icon: const Icon(
            Icons.replay,
          ),
        )
      ];
    });
  }

  @override
  Widget build(BuildContext context) => ListItem.open(
      title: Text(appLocalizations.bypassDomain),
      subtitle: Text(appLocalizations.bypassDomainDesc),
      delegate: OpenDelegate(
        blur: false,
        title: appLocalizations.bypassDomain,
        widget: Consumer(
          builder: (_, ref, __) {
            _initActions(context, ref);
            final bypassDomain = ref.watch(
                networkSettingProvider.select((state) => state.bypassDomain));
            return ListInputPage(
              title: appLocalizations.bypassDomain,
              items: bypassDomain,
              titleBuilder: Text.new,
              onChange: (items) {
                ref.read(networkSettingProvider.notifier).updateState(
                      (state) => state.copyWith(
                        bypassDomain: List.from(items),
                      ),
                    );
              },
            );
          },
        ),
      ),
    );
}

class RouteModeItem extends ConsumerWidget {
  const RouteModeItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeMode =
        ref.watch(networkSettingProvider.select((state) => state.routeMode));
    return ListItem<RouteMode>.options(
      title: Text(appLocalizations.routeMode),
      subtitle: Text(Intl.message("routeMode_${routeMode.name}")),
      delegate: OptionsDelegate<RouteMode>(
        title: appLocalizations.routeMode,
        options: RouteMode.values,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref.read(networkSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  routeMode: value,
                ),
              );
        },
        textBuilder: (routeMode) => Intl.message(
          "routeMode_${routeMode.name}",
        ),
        value: routeMode,
      ),
    );
  }
}

class RouteAddressItem extends ConsumerWidget {
  const RouteAddressItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bypassPrivate = ref.watch(networkSettingProvider
        .select((state) => state.routeMode == RouteMode.bypassPrivate));
    if (bypassPrivate) {
      return Container();
    }
    return ListItem.open(
      title: Text(appLocalizations.routeAddress),
      subtitle: Text(appLocalizations.routeAddressDesc),
      delegate: OpenDelegate(
        blur: false,
        maxWidth: 360,
        title: appLocalizations.routeAddress,
        widget: Consumer(
          builder: (_, ref, __) {
            final routeAddress = ref.watch(
              patchClashConfigProvider.select(
                (state) => state.tun.routeAddress,
              ),
            );
            return ListInputPage(
              title: appLocalizations.routeAddress,
              items: routeAddress,
              titleBuilder: Text.new,
              onChange: (items) {
                ref.read(patchClashConfigProvider.notifier).updateState(
                      (state) => state.copyWith.tun(
                        routeAddress: List.from(items),
                      ),
                    );
              },
            );
          },
        ),
      ),
    );
  }
}

final networkItems = [
  if (Platform.isAndroid) const VPNItem(),
  if (Platform.isAndroid)
    ...generateSection(
      title: "VPN",
      items: [
        const VpnSystemProxyItem(),
        const BypassDomainItem(),
        const AllowBypassItem(),
        const Ipv6Item(),
      ],
    ),
  if (system.isDesktop)
    ...generateSection(
      title: appLocalizations.system,
      items: [
        const SystemProxyItem(),
        const BypassDomainItem(),
      ],
    ),
  ...generateSection(
    title: appLocalizations.options,
    items: [
      const OverrideNetworkSettingsItemNetwork(),
      if (system.isDesktop) const TUNItem(),
      if (Platform.isMacOS) const AutoSetSystemDnsItem(),
      const TunStackItem(),
      if (!system.isDesktop) ...[
        const RouteModeItem(),
        const RouteAddressItem(),
      ]
    ],
  ),
];

class NetworkListView extends ConsumerWidget {
  const NetworkListView({super.key});

  void _initActions(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      context.commonScaffoldState?.actions = [
        IconButton(
          onPressed: () async {
            final res = await globalState.showMessage(
              title: appLocalizations.reset,
              message: TextSpan(
                text: appLocalizations.resetTip,
              ),
            );
            if (res != true) {
              return;
            }
            ref.read(vpnSettingProvider.notifier).updateState(
                  (state) => defaultVpnProps.copyWith(
                    accessControl: state.accessControl,
                  ),
                );
            ref.read(patchClashConfigProvider.notifier).updateState(
                  (state) => state.copyWith(
                    tun: defaultTun,
                  ),
                );
          },
          tooltip: appLocalizations.reset,
          icon: const Icon(
            Icons.replay,
          ),
        )
      ];
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _initActions(context, ref);
    return generateListView(
      networkItems,
    );
  }
}
