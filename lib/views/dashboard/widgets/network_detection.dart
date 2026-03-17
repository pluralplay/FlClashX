import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkDetection extends ConsumerStatefulWidget {
  const NetworkDetection({super.key});

  @override
  ConsumerState<NetworkDetection> createState() => _NetworkDetectionState();
}

class _NetworkDetectionState extends ConsumerState<NetworkDetection> {
  String _countryCodeToEmoji(String countryCode) {
    final code = countryCode.toUpperCase();
    if (code.length != 2) {
      return countryCode;
    }
    final firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: getWidgetHeight(1),
      child: ValueListenableBuilder<NetworkDetectionState>(
        valueListenable: detectionState.state,
        builder: (_, state, __) {
          final ipInfo = state.ipInfo;
          final isLoading = state.isLoading;
          return CommonCard(
            onPressed: () {
              final success = detectionState.forceCheck();
              if (!success) {
                globalState.showMessage(
                  title: appLocalizations.tip,
                  message: TextSpan(
                    text: appLocalizations.tooFrequentOperation,
                  ),
                );
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  height: globalState.measure.titleMediumHeight + 16,
                  padding: baseInfoEdgeInsets.copyWith(
                    bottom: 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      ipInfo != null
                          ? Text(
                              _countryCodeToEmoji(
                                ipInfo.countryCode,
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.toLight
                                  .copyWith(
                                    fontFamily: FontFamily.twEmoji.value,
                                  ),
                            )
                          : Icon(
                              Icons.network_check,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      const SizedBox(
                        width: 8,
                      ),
                      Flexible(
                        flex: 1,
                        child: TooltipText(
                          text: Text(
                            appLocalizations.networkDetection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      AspectRatio(
                        aspectRatio: 1,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            globalState.showMessage(
                              title: appLocalizations.tip,
                              message: TextSpan(
                                text: appLocalizations.detectionTip,
                              ),
                              cancelable: false,
                            );
                          },
                          icon: Icon(
                            size: 16.ap,
                            Icons.info_outline,
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: baseInfoEdgeInsets.copyWith(
                      top: 0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FadeThroughBox(
                        child: ipInfo != null
                            ? TooltipText(
                                text: Text(
                                  ipInfo.ip,
                                  style: context.textTheme.bodyMedium?.toLight
                                      .adjustSize(1),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : FadeThroughBox(
                                child: isLoading == false && ipInfo == null
                                    ? Text(
                                        "timeout",
                                        style: context.textTheme.bodyMedium
                                            ?.copyWith(color: Colors.red)
                                            .adjustSize(1),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : Container(
                                        padding: const EdgeInsets.all(2),
                                        child: const AspectRatio(
                                          aspectRatio: 1,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                              ),
                      ),
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
}
