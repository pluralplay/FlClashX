import 'dart:convert';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/common.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChangeServerButton extends ConsumerWidget {
  const ChangeServerButton({super.key});

  String? _decodeBase64IfNeeded(String? value) {
    if (value == null || value.isEmpty) return value;

    try {
      final decoded = utf8.decode(base64.decode(value));
      return decoded;
    } catch (e) {
      return value;
    }
  }

  String? _extractFlag(String text) {
    final runes = text.runes.toList();

    for (var i = 0; i < runes.length - 1; i++) {
      final first = runes[i];
      final second = runes[i + 1];

      if (first >= 0x1F1E6 &&
          first <= 0x1F1FF &&
          second >= 0x1F1E6 &&
          second <= 0x1F1FF) {
        return String.fromCharCodes([first, second]);
      }
    }

    return null;
  }

  String _removeFlagFromText(String text) {
    final runes = text.runes.toList();
    final result = <int>[];

    var i = 0;
    while (i < runes.length) {
      final current = runes[i];

      if (current >= 0x1F1E6 && current <= 0x1F1FF && i + 1 < runes.length) {
        final next = runes[i + 1];

        if (next >= 0x1F1E6 && next <= 0x1F1FF) {
          i += 2;
          continue;
        }
      }

      result.add(current);
      i++;
    }

    return String.fromCharCodes(result).trim();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);

    if (profile == null) {
      return const SizedBox.shrink();
    }

    final serverInfoGroupName = _decodeBase64IfNeeded(
      profile.providerHeaders['flclashx-serverinfo'],
    );

    if (serverInfoGroupName == null || serverInfoGroupName.isEmpty) {
      return _buildSimpleButton(context);
    }

    final group = ref.watch(
      currentGroupsStateProvider.select(
        (state) => state.value.getGroup(serverInfoGroupName),
      ),
    );

    if (group == null) {
      return _buildSimpleButton(context);
    }

    final currentServerName = group.now ?? '-';

    final currentProxy = group.all.firstWhere(
      (proxy) => proxy.name == currentServerName,
      orElse: () => Proxy(
        name: currentServerName,
        type: '-',
        serverDescription: null,
      ),
    );

    var flag = _extractFlag(currentProxy.name);
    if (flag == null && currentProxy.serverDescription != null) {
      flag = _extractFlag(currentProxy.serverDescription!);
    }

    final nameWithoutFlag = _removeFlagFromText(currentProxy.name);

    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          globalState.appController.toPage(PageLabel.proxies);
        },
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.colorScheme.primary.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: flag != null
                      ? Text(
                          flag,
                          style: TextStyle(
                            fontSize: 24,
                            height: 1.0,
                            fontFamily: FontFamily.twEmoji.value,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : Icon(
                          Icons.dns_rounded,
                          size: 24,
                          color: context.colorScheme.primary,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nameWithoutFlag,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Consumer(
                builder: (context, ref, _) {
                  final delay = ref.watch(getDelayProvider(
                    proxyName: currentProxy.name,
                    testUrl: group.testUrl,
                  ));

                  if (delay == null || delay <= 0) {
                    return const SizedBox.shrink();
                  }

                  final delayColor =
                      utils.getDelayColor(delay) ?? context.colorScheme.primary;

                  return Container(
                    width: 56,
                    height: 38,
                    decoration: BoxDecoration(
                      color: delayColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: delayColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$delay ms',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: delayColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.swap_horizontal_circle,
                  size: 22,
                  color: context.colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleButton(BuildContext context) => SizedBox(
        height: getWidgetHeight(1),
        child: CommonCard(
          onPressed: () {
            globalState.appController.toPage(PageLabel.proxies);
          },
          child: Container(
            padding: baseInfoEdgeInsets.copyWith(
              top: 6,
              bottom: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        context.colorScheme.primary.withValues(alpha: 0.15),
                        context.colorScheme.primary.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: context.colorScheme.primary.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.language_rounded,
                    size: 22,
                    color: context.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    appLocalizations.changeServer,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: context.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.swap_horizontal_circle,
                    size: 22,
                    color: context.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
