import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class OutboundMode extends StatelessWidget {
  const OutboundMode({super.key});

  @override
  Widget build(BuildContext context) {
    final height = getWidgetHeight(2);
    return SizedBox(
      height: height,
      child: Consumer(
        builder: (_, ref, __) {
          final mode = ref.watch(
            patchClashConfigProvider.select(
              (state) => state.mode,
            ),
          );
          return Theme(
              data: Theme.of(context).copyWith(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent),
              child: CommonCard(
                onPressed: () {},
                info: Info(
                  label: appLocalizations.outboundMode,
                  iconData: Icons.call_split_sharp,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    bottom: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final item in Mode.values)
                        Flexible(
                          fit: FlexFit.tight,
                          child: ListItem.radio(
                            dense: true,
                            horizontalTitleGap: 4,
                            padding: EdgeInsets.only(
                              left: 12.ap,
                              right: 16.ap,
                            ),
                            delegate: RadioDelegate(
                              value: item,
                              groupValue: mode,
                              onChanged: (value) async {
                                if (value == null) {
                                  return;
                                }
                                globalState.appController.changeMode(value);
                              },
                            ),
                            title: Text(
                              Intl.message(item.name),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.toSoftBold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ));
        },
      ),
    );
  }
}

class OutboundModeV2 extends StatelessWidget {
  const OutboundModeV2({super.key});

  Color _getTextColor(BuildContext context, Mode mode) => switch (mode) {
      Mode.rule => context.colorScheme.onSecondaryContainer,
      Mode.global => context.colorScheme.onPrimaryContainer,
      Mode.direct => context.colorScheme.onTertiaryContainer,
    };

  @override
  Widget build(BuildContext context) {
    final height = getWidgetHeight(0.72);
    return SizedBox(
      height: height,
      child: CommonCard(
        padding: EdgeInsets.zero,
        child: Consumer(
          builder: (_, ref, __) {
            final mode = ref.watch(
              patchClashConfigProvider.select(
                (state) => state.mode,
              ),
            );
            final thumbColor = switch (mode) {
              Mode.rule => context.colorScheme.secondaryContainer,
              Mode.global => globalState.theme.darken3PrimaryContainer,
              Mode.direct => context.colorScheme.tertiaryContainer,
            };
            return Container(
              constraints: const BoxConstraints.expand(),
              child: CommonTabBar<Mode>(
                children: Map.fromEntries(
                  Mode.values.map(
                    (item) => MapEntry(
                      item,
                      Container(
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(),
                        height: height - 16,
                        child: Text(
                          Intl.message(item.name),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.adjustSize(1)
                              .copyWith(
                                color: item == mode
                                    ? _getTextColor(
                                        context,
                                        item,
                                      )
                                    : null,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                groupValue: mode,
                onValueChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  globalState.appController.changeMode(value);
                },
                thumbColor: thumbColor,
              ),
            );
          },
        ),
      ),
    );
  }
}
