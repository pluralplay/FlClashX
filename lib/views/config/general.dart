import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OverrideNetworkSettingsItem extends ConsumerWidget {
  const OverrideNetworkSettingsItem({super.key});

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
              if (!value) {
                // Turning override off — re-pull the provider YAML so cached
                // override values (e.g. auth creds) don't leak into the
                // "managed by provider" state.
                globalState.appController.setupClashConfigDebounce();
              }
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

class LogLevelItem extends ConsumerWidget {
  const LogLevelItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logLevel =
        ref.watch(patchClashConfigProvider.select((state) => state.logLevel));
    return ListItem<LogLevel>.options(
      leading: const Icon(Icons.info_outline),
      title: Text(appLocalizations.logLevel),
      subtitle: Text(logLevel.name),
      delegate: OptionsDelegate<LogLevel>(
        title: appLocalizations.logLevel,
        options: LogLevel.values,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith(
                  logLevel: value,
                ),
              );
        },
        textBuilder: (logLevel) => logLevel.name,
        value: logLevel,
      ),
    );
  }
}

class UaItem extends ConsumerWidget {
  const UaItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalUa =
        ref.watch(patchClashConfigProvider.select((state) => state.globalUa));
    return ListItem<String?>.options(
      leading: const Icon(Icons.computer_outlined),
      title: const Text("UA"),
      subtitle: Text(globalUa ?? appLocalizations.defaultText),
      delegate: OptionsDelegate<String?>(
        title: "UA",
        options: [
          null,
          "clashx-verge/v1.6.6",
          "ClashforWindows/0.19.23",
        ],
        value: globalUa,
        onChanged: (value) {
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith(
                  globalUa: value,
                ),
              );
        },
        textBuilder: (ua) => ua ?? appLocalizations.defaultText,
      ),
    );
  }
}

class KeepAliveIntervalItem extends ConsumerWidget {
  const KeepAliveIntervalItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepAliveInterval = ref.watch(
        patchClashConfigProvider.select((state) => state.keepAliveInterval));
    return ListItem.input(
      leading: const Icon(Icons.timer_outlined),
      title: Text(appLocalizations.keepAliveIntervalDesc),
      subtitle: Text("$keepAliveInterval ${appLocalizations.seconds}"),
      delegate: InputDelegate(
        title: appLocalizations.keepAliveIntervalDesc,
        suffixText: appLocalizations.seconds,
        resetValue: "$defaultKeepAliveInterval",
        value: "$keepAliveInterval",
        validator: (value) {
          if (value == null || value.isEmpty) {
            return appLocalizations.emptyTip(appLocalizations.interval);
          }
          final intValue = int.tryParse(value);
          if (intValue == null) {
            return appLocalizations.numberTip(appLocalizations.interval);
          }
          return null;
        },
        onChanged: (value) {
          if (value == null) {
            return;
          }
          final intValue = int.parse(value);
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith(
                  keepAliveInterval: intValue,
                ),
              );
        },
      ),
    );
  }
}

class TestUrlItem extends ConsumerWidget {
  const TestUrlItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testUrl =
        ref.watch(appSettingProvider.select((state) => state.testUrl));
    return ListItem.input(
      leading: const Icon(Icons.timeline),
      title: Text(appLocalizations.testUrl),
      subtitle: Text(testUrl),
      delegate: InputDelegate(
        resetValue: defaultTestUrl,
        title: appLocalizations.testUrl,
        value: testUrl,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return appLocalizations.emptyTip(appLocalizations.testUrl);
          }
          if (!value.isUrl) {
            return appLocalizations.urlTip(appLocalizations.testUrl);
          }
          return null;
        },
        onChanged: (value) {
          if (value == null) {
            return;
          }
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  testUrl: value,
                ),
              );
        },
      ),
    );
  }
}

class PortItem extends ConsumerWidget {
  const PortItem({super.key});

  Future<void> handleShowPortDialog() async {
    await globalState.showCommonDialog(
      child: const _PortDialog(),
    );
    // inputDelegate.onChanged(value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mixedPort =
        ref.watch(patchClashConfigProvider.select((state) => state.mixedPort));
    final overrideNetworkSettings = ref.watch(
      appSettingProvider.select((state) => state.overrideNetworkSettings),
    );
    final isEnabled = overrideNetworkSettings;
    
    return AbsorbPointer(
      absorbing: !isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: ListItem(
          leading: const Icon(Icons.adjust_outlined),
          title: Text(appLocalizations.port),
          subtitle: Text("$mixedPort"),
          onTap: handleShowPortDialog,
          // delegate: InputDelegate(
          //   title: appLocalizations.port,
          //   value: "$mixedPort",
          //   validator: (String? value) {
          //     if (value == null || value.isEmpty) {
          //       return appLocalizations.emptyTip(appLocalizations.proxyPort);
          //     }
          //     final mixedPort = int.tryParse(value);
          //     if (mixedPort == null) {
          //       return appLocalizations.numberTip(appLocalizations.proxyPort);
          //     }
          //     if (mixedPort < 1024 || mixedPort > 49151) {
          //       return appLocalizations.proxyPortTip;
          //     }
          //     return null;
          //   },
          //   onChanged: (String? value) {
          //     if (value == null) {
          //       return;
          //     }
          //     final mixedPort = int.parse(value);
          //     ref.read(patchClashConfigProvider.notifier).updateState(
          //           (state) => state.copyWith(
          //             mixedPort: mixedPort,
          //           ),
          //         );
          //   },
          //   resetValue: "$defaultMixedPort",
          // ),
        ),
      ),
    );
  }
}

class PortAuthenticationItem extends ConsumerWidget {
  const PortAuthenticationItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(
      appSettingProvider.select((s) => s.overrideNetworkSettings),
    );

    if (!override) {
      // Provider-driven: not user-editable. Subtitle mirrors whether the
      // profile brought its own creds; tap opens a read-only review dialog
      // when there's anything to show.
      final providerAuth = ref.watch(
        patchClashConfigProvider.select((s) => s.authentication),
      );
      final hasCreds = providerAuth.isNotEmpty;
      return Opacity(
        opacity: 0.5,
        child: ListItem(
          leading: const Icon(Icons.lock_outline),
          title: Text(appLocalizations.portAuthentication),
          subtitle: Text(
            hasCreds
                ? appLocalizations.portAuthEnabledByProvider
                : appLocalizations.portAuthNotEnabledByProvider,
          ),
          onTap: hasCreds
              ? () => globalState.showCommonDialog(
                    child: const _PortAuthDialog(readOnly: true),
                  )
              : null,
        ),
      );
    }

    // Override mode: trailing Switch toggles enabled/disabled (persistent
    // app setting). Tapping elsewhere opens the edit dialog.
    final enabled = ref.watch(
      appSettingProvider.select((s) => s.portAuthOverrideEnabled),
    );
    return ListItem(
      leading: const Icon(Icons.lock_outline),
      title: Text(appLocalizations.portAuthentication),
      subtitle: Text(appLocalizations.portAuthTapToChange),
      trailing: Switch(
        value: enabled,
        onChanged: (value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(portAuthOverrideEnabled: value),
              );
        },
      ),
      onTap: () => globalState.showCommonDialog(
        child: const _PortAuthDialog(readOnly: false),
      ),
    );
  }
}

class HostsItem extends StatelessWidget {
  const HostsItem({super.key});

  @override
  Widget build(BuildContext context) => ListItem.open(
      leading: const Icon(Icons.view_list_outlined),
      title: const Text("Hosts"),
      subtitle: Text(appLocalizations.hostsDesc),
      delegate: OpenDelegate(
        blur: false,
        title: "Hosts",
        widget: Consumer(
          builder: (_, ref, __) {
            final hosts = ref
                .watch(patchClashConfigProvider.select((state) => state.hosts));
            return MapInputPage(
              title: "Hosts",
              map: hosts,
              titleBuilder: (item) => Text(item.key),
              subtitleBuilder: (item) => Text(item.value),
              onChange: (value) {
                ref.read(patchClashConfigProvider.notifier).updateState(
                      (state) => state.copyWith(
                        hosts: value,
                      ),
                    );
              },
            );
          },
        ),
      ),
    );
}

class SendHeadersToggle extends StatefulWidget {
  const SendHeadersToggle({super.key});

  @override
  State<SendHeadersToggle> createState() => _SendHeadersToggleState();
}

class _SendHeadersToggleState extends State<SendHeadersToggle> {
  static const _preferenceKey = 'sendDeviceHeaders';
  bool _sendHeaders = true;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _sendHeaders = prefs.getBool(_preferenceKey) ?? true;
      });
    }
  }

  Future<void> _updatePreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey, value);
    setState(() {
      _sendHeaders = value;
    });
  }

  @override
  Widget build(BuildContext context) => ListItem.switchItem(
      leading: const Icon(Icons.perm_device_information_outlined),
      title: Text(appLocalizations.settingsSendDeviceDataTitle),
      subtitle: Text(appLocalizations.settingsSendDeviceDataSubtitle),
      delegate: SwitchDelegate(
        value: _sendHeaders,
        onChanged: _updatePreference,
      ),
    );
}

class Ipv6Item extends ConsumerWidget {
  const Ipv6Item({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ipv6 =
        ref.watch(patchClashConfigProvider.select((state) => state.ipv6));
    final overrideNetworkSettings = ref.watch(
      appSettingProvider.select((state) => state.overrideNetworkSettings),
    );
    final isEnabled = overrideNetworkSettings;
    
    return AbsorbPointer(
      absorbing: !isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: ListItem.switchItem(
          leading: const Icon(Icons.water_outlined),
          title: const Text("IPv6"),
          subtitle: Text(appLocalizations.ipv6Desc),
          delegate: SwitchDelegate(
            value: ipv6,
            onChanged: (value) async {
              ref.read(patchClashConfigProvider.notifier).updateState(
                    (state) => state.copyWith(
                      ipv6: value,
                    ),
                  );
              globalState.appController.updateClashConfigDebounce();
            },
          ),
        ),
      ),
    );
  }
}

class AllowLanItem extends ConsumerWidget {
  const AllowLanItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowLan =
        ref.watch(patchClashConfigProvider.select((state) => state.allowLan));
    final overrideNetworkSettings = ref.watch(
      appSettingProvider.select((state) => state.overrideNetworkSettings),
    );
    final isEnabled = overrideNetworkSettings;
    
    return AbsorbPointer(
      absorbing: !isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: ListItem.switchItem(
          leading: const Icon(Icons.device_hub),
          title: Text(appLocalizations.allowLan),
          subtitle: Text(appLocalizations.allowLanDesc),
          delegate: SwitchDelegate(
            value: allowLan,
            onChanged: (value) async {
              ref.read(patchClashConfigProvider.notifier).updateState(
                    (state) => state.copyWith(
                      allowLan: value,
                    ),
                  );
              globalState.appController.updateClashConfigDebounce();
            },
          ),
        ),
      ),
    );
  }
}

class UnifiedDelayItem extends ConsumerWidget {
  const UnifiedDelayItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unifiedDelay = ref
        .watch(patchClashConfigProvider.select((state) => state.unifiedDelay));

    return ListItem.switchItem(
      leading: const Icon(Icons.compress_outlined),
      title: Text(appLocalizations.unifiedDelay),
      subtitle: Text(appLocalizations.unifiedDelayDesc),
      delegate: SwitchDelegate(
        value: unifiedDelay,
        onChanged: (value) async {
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith(
                  unifiedDelay: value,
                ),
              );
        },
      ),
    );
  }
}

class FindProcessItem extends ConsumerWidget {
  const FindProcessItem({super.key});

  String _getFindProcessModeLabel(FindProcessMode mode) {
    switch (mode) {
      case FindProcessMode.off:
        return 'Off';
      case FindProcessMode.strict:
        return 'Strict';
      case FindProcessMode.always:
        return 'Always';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final findProcessMode = ref.watch(
      patchClashConfigProvider.select((state) => state.findProcessMode),
    );
    final overrideNetworkSettings = ref.watch(
      appSettingProvider.select((state) => state.overrideNetworkSettings),
    );
    final isEnabled = overrideNetworkSettings;

    return AbsorbPointer(
      absorbing: !isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: ListItem<FindProcessMode>.options(
          leading: const Icon(Icons.polymer_outlined),
          title: Text(appLocalizations.findProcessMode),
          subtitle: Text(_getFindProcessModeLabel(findProcessMode)),
          delegate: OptionsDelegate<FindProcessMode>(
            title: appLocalizations.findProcessMode,
            options: FindProcessMode.values,
            onChanged: (value) async {
              if (value == null) return;
              ref.read(patchClashConfigProvider.notifier).updateState(
                    (state) => state.copyWith(
                      findProcessMode: value,
                    ),
                  );
              globalState.appController.updateClashConfigDebounce();
            },
            textBuilder: _getFindProcessModeLabel,
            value: findProcessMode,
          ),
        ),
      ),
    );
  }
}

class TcpConcurrentItem extends ConsumerWidget {
  const TcpConcurrentItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tcpConcurrent = ref
        .watch(patchClashConfigProvider.select((state) => state.tcpConcurrent));
    return ListItem.switchItem(
      leading: const Icon(Icons.double_arrow_outlined),
      title: Text(appLocalizations.tcpConcurrent),
      subtitle: Text(appLocalizations.tcpConcurrentDesc),
      delegate: SwitchDelegate(
        value: tcpConcurrent,
        onChanged: (value) async {
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith(
                  tcpConcurrent: value,
                ),
              );
        },
      ),
    );
  }
}

class GeodataLoaderItem extends ConsumerWidget {
  const GeodataLoaderItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMemconservative = ref.watch(patchClashConfigProvider.select(
        (state) => state.geodataLoader == GeodataLoader.memconservative));
    return ListItem.switchItem(
      leading: const Icon(Icons.memory),
      title: Text(appLocalizations.geodataLoader),
      subtitle: Text(appLocalizations.geodataLoaderDesc),
      delegate: SwitchDelegate(
        value: isMemconservative,
        onChanged: (value) async {
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith(
                  geodataLoader: value
                      ? GeodataLoader.memconservative
                      : GeodataLoader.standard,
                ),
              );
        },
      ),
    );
  }
}

class ExternalControllerItem extends ConsumerWidget {
  const ExternalControllerItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasExternalController = ref.watch(patchClashConfigProvider.select(
        (state) => state.externalController == ExternalControllerStatus.open));
    return ListItem.switchItem(
      leading: const Icon(Icons.api_outlined),
      title: Text(appLocalizations.externalController),
      subtitle: Text(appLocalizations.externalControllerDesc),
      delegate: SwitchDelegate(
        value: hasExternalController,
        onChanged: (value) async {
          ref.read(patchClashConfigProvider.notifier).updateState(
                (state) => state.copyWith(
                  externalController: value
                      ? ExternalControllerStatus.open
                      : ExternalControllerStatus.close,
                ),
              );
        },
      ),
    );
  }
}

final generalItems = <Widget>[
  const OverrideNetworkSettingsItem(),
  const LogLevelItem(),
  const UaItem(),
  if (system.isDesktop) const KeepAliveIntervalItem(),
  const TestUrlItem(),
  const PortItem(),
  const PortAuthenticationItem(),
  const HostsItem(),
  const SendHeadersToggle(),
  const Ipv6Item(),
  const AllowLanItem(),
  const UnifiedDelayItem(),
  const FindProcessItem(),
  const TcpConcurrentItem(),
  const GeodataLoaderItem(),
  const ExternalControllerItem(),
]
    .separated(
      const Divider(
        height: 0,
      ),
    )
    .toList();

class _PortDialog extends ConsumerStatefulWidget {
  const _PortDialog();

  @override
  ConsumerState<_PortDialog> createState() => _PortDialogState();
}

class _PortDialogState extends ConsumerState<_PortDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isMore = false;

  late TextEditingController _mixedPortController;
  late TextEditingController _portController;
  late TextEditingController _socksPortController;
  late TextEditingController _redirPortController;
  late TextEditingController _tProxyPortController;

  @override
  void initState() {
    super.initState();
    final vm5 = ref.read(patchClashConfigProvider.select((state) => VM5(
        a: state.mixedPort,
        b: state.port,
        c: state.socksPort,
        d: state.redirPort,
        e: state.tproxyPort,
      )));
    _mixedPortController = TextEditingController(
      text: vm5.a.toString(),
    );
    _portController = TextEditingController(
      text: vm5.b.toString(),
    );
    _socksPortController = TextEditingController(
      text: vm5.c.toString(),
    );
    _redirPortController = TextEditingController(
      text: vm5.d.toString(),
    );
    _tProxyPortController = TextEditingController(
      text: vm5.e.toString(),
    );
  }

  Future<void> _handleReset() async {
    final res = await globalState.showMessage(
      message: TextSpan(
        text: appLocalizations.resetTip,
      ),
    );
    if (res != true) {
      return;
    }
    ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(
            mixedPort: 7890,
            port: 0,
            socksPort: 0,
            redirPort: 0,
            tproxyPort: 0,
          ),
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleUpdate() {
    if (_formKey.currentState?.validate() == false) return;
    ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(
            mixedPort: int.parse(_mixedPortController.text),
            port: int.parse(_portController.text),
            socksPort: int.parse(_socksPortController.text),
            redirPort: int.parse(_redirPortController.text),
            tproxyPort: int.parse(_tProxyPortController.text),
          ),
        );
    Navigator.of(context).pop();
  }

  void _handleMore() {
    setState(() {
      _isMore = !_isMore;
    });
  }

  @override
  Widget build(BuildContext context) => CommonDialog(
      title: appLocalizations.port,
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              onPressed: _handleMore,
              icon: CommonExpandIcon(
                expand: _isMore,
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: _handleReset,
                  child: Text(appLocalizations.reset),
                ),
                const SizedBox(
                  width: 4,
                ),
                TextButton(
                  onPressed: _handleUpdate,
                  child: Text(appLocalizations.submit),
                )
              ],
            )
          ],
        )
      ],
      child: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AnimatedSize(
            duration: midDuration,
            curve: Curves.easeOutQuad,
            alignment: Alignment.topCenter,
            child: Column(
              spacing: 24,
              children: [
                TextFormField(
                  keyboardType: TextInputType.url,
                  maxLines: 1,
                  minLines: 1,
                  controller: _mixedPortController,
                  onFieldSubmitted: (_) {
                    _handleUpdate();
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: appLocalizations.mixedPort,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return appLocalizations
                          .emptyTip(appLocalizations.mixedPort);
                    }
                    final port = int.tryParse(value);
                    if (port == null) {
                      return appLocalizations
                          .numberTip(appLocalizations.mixedPort);
                    }
                    if (port < 1024 || port > 49151) {
                      return appLocalizations
                          .portTip(appLocalizations.mixedPort);
                    }
                    final ports = [
                      _portController.text,
                      _socksPortController.text,
                      _tProxyPortController.text,
                      _redirPortController.text
                    ].map((item) => item.trim());
                    if (ports.contains(value.trim())) {
                      return appLocalizations.portConflictTip;
                    }
                    return null;
                  },
                ),
                if (_isMore) ...[
                  TextFormField(
                    keyboardType: TextInputType.url,
                    maxLines: 1,
                    minLines: 1,
                    controller: _portController,
                    onFieldSubmitted: (_) {
                      _handleUpdate();
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: appLocalizations.port,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return appLocalizations.emptyTip(appLocalizations.port);
                      }
                      final port = int.tryParse(value);
                      if (port == null) {
                        return appLocalizations.numberTip(
                          appLocalizations.port,
                        );
                      }
                      if (port == 0) {
                        return null;
                      }
                      if (port < 1024 || port > 49151) {
                        return appLocalizations.portTip(appLocalizations.port);
                      }
                      final ports = [
                        _mixedPortController.text,
                        _socksPortController.text,
                        _tProxyPortController.text,
                        _redirPortController.text
                      ].map((item) => item.trim());
                      if (ports.contains(value.trim())) {
                        return appLocalizations.portConflictTip;
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    keyboardType: TextInputType.url,
                    maxLines: 1,
                    minLines: 1,
                    controller: _socksPortController,
                    onFieldSubmitted: (_) {
                      _handleUpdate();
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: appLocalizations.socksPort,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return appLocalizations
                            .emptyTip(appLocalizations.socksPort);
                      }
                      final port = int.tryParse(value);
                      if (port == null) {
                        return appLocalizations
                            .numberTip(appLocalizations.socksPort);
                      }
                      if (port == 0) {
                        return null;
                      }
                      if (port < 1024 || port > 49151) {
                        return appLocalizations
                            .portTip(appLocalizations.socksPort);
                      }
                      final ports = [
                        _portController.text,
                        _mixedPortController.text,
                        _tProxyPortController.text,
                        _redirPortController.text
                      ].map((item) => item.trim());
                      if (ports.contains(value.trim())) {
                        return appLocalizations.portConflictTip;
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    keyboardType: TextInputType.url,
                    maxLines: 1,
                    minLines: 1,
                    controller: _redirPortController,
                    onFieldSubmitted: (_) {
                      _handleUpdate();
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: appLocalizations.redirPort,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return appLocalizations
                            .emptyTip(appLocalizations.redirPort);
                      }
                      final port = int.tryParse(value);
                      if (port == null) {
                        return appLocalizations
                            .numberTip(appLocalizations.redirPort);
                      }
                      if (port == 0) {
                        return null;
                      }
                      if (port < 1024 || port > 49151) {
                        return appLocalizations
                            .portTip(appLocalizations.redirPort);
                      }
                      final ports = [
                        _portController.text,
                        _socksPortController.text,
                        _tProxyPortController.text,
                        _mixedPortController.text
                      ].map((item) => item.trim());
                      if (ports.contains(value.trim())) {
                        return appLocalizations.portConflictTip;
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    keyboardType: TextInputType.url,
                    maxLines: 1,
                    minLines: 1,
                    controller: _tProxyPortController,
                    onFieldSubmitted: (_) {
                      _handleUpdate();
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: appLocalizations.tproxyPort,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return appLocalizations
                            .emptyTip(appLocalizations.tproxyPort);
                      }
                      final port = int.tryParse(value);
                      if (port == null) {
                        return appLocalizations
                            .numberTip(appLocalizations.tproxyPort);
                      }
                      if (port == 0) {
                        return null;
                      }
                      if (port < 1024 || port > 49151) {
                        return appLocalizations.portTip(
                          appLocalizations.tproxyPort,
                        );
                      }
                      final ports = [
                        _portController.text,
                        _socksPortController.text,
                        _mixedPortController.text,
                        _redirPortController.text
                      ].map((item) => item.trim());
                      if (ports.contains(value.trim())) {
                        return appLocalizations.portConflictTip;
                      }

                      return null;
                    },
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
}

class _PortAuthDialog extends ConsumerStatefulWidget {
  const _PortAuthDialog({this.readOnly = false});

  final bool readOnly;

  @override
  ConsumerState<_PortAuthDialog> createState() => _PortAuthDialogState();
}

class _PortAuthDialogState extends ConsumerState<_PortAuthDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _reviewController;

  @override
  void initState() {
    super.initState();
    final appSetting = ref.read(appSettingProvider);
    _userController = TextEditingController(
      text: appSetting.portAuthOverrideUsername,
    );
    _passController = TextEditingController(
      text: appSetting.portAuthOverridePassword,
    );
    final auth = ref.read(patchClashConfigProvider).authentication;
    _reviewController = TextEditingController(text: auth.join('\n'));
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  void _handleRegenerate() {
    _passController.text = GlobalState.randomPortAuthPassword();
  }

  void _handleUpdate() {
    if (_formKey.currentState?.validate() == false) return;
    final user = _userController.text;
    final pass = _passController.text;
    ref.read(appSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            portAuthOverrideUsername: user,
            portAuthOverridePassword: pass,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      // Review mode: show all provider-supplied entries verbatim, one per line,
      // so the user can copy-paste.
      return CommonDialog(
        title: appLocalizations.portAuthentication,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _reviewController,
            readOnly: true,
            maxLines: null,
            minLines: 3,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['RobotoMono', 'Courier'],
            ),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
      );
    }

    // Edit mode — single user/pass pair stored on AppSetting.
    return CommonDialog(
      title: appLocalizations.portAuthentication,
      actions: [
        TextButton(
          onPressed: _handleRegenerate,
          child: Text(appLocalizations.reset),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: _handleUpdate,
          child: Text(appLocalizations.submit),
        ),
      ],
      child: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            spacing: 24,
            children: [
              TextFormField(
                controller: _userController,
                maxLines: 1,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_circle_outlined),
                  border: const OutlineInputBorder(),
                  labelText: appLocalizations.username,
                ),
                validator: (value) {
                  if (value != null && value.contains(':')) {
                    return "':'";
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passController,
                maxLines: 1,
                onFieldSubmitted: (_) => _handleUpdate(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: const OutlineInputBorder(),
                  labelText: appLocalizations.password,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
