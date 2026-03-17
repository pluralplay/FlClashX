import 'dart:math';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'common.dart';

typedef GroupNameProxiesMap = Map<String, List<Proxy>>;

class ProxiesListView extends StatefulWidget {
  const ProxiesListView({super.key});

  @override
  State<ProxiesListView> createState() => _ProxiesListViewState();
}

class _ProxiesListViewState extends State<ProxiesListView> {
  final _controller = ScrollController();
  final _headerStateNotifier = ValueNotifier<ProxiesListHeaderSelectorState>(
    const ProxiesListHeaderSelectorState(
      offset: 0,
      currentIndex: 0,
    ),
  );
  final List<double> _headerOffset = [];
  GroupNameProxiesMap _lastGroupNameProxiesMap = {};

  int _lastGroupsVersion = 0;
  List<String> _lastGroupNames = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_adjustHeader);
  }

  void _adjustHeader() {
    final offset = _controller.offset;
    final index = _headerOffset.findInterval(offset);
    final currentIndex = index;
    var headerOffset = 0.0;
    if (index + 1 <= _headerOffset.length - 1) {
      final endOffset = _headerOffset[index + 1];
      final startOffset = endOffset - listHeaderHeight - 8;
      if (offset > startOffset && offset < endOffset) {
        headerOffset = offset - startOffset;
      }
    }
    _headerStateNotifier.value = _headerStateNotifier.value.copyWith(
      currentIndex: currentIndex,
      offset: max(headerOffset, 0),
    );
  }

  @override
  void dispose() {
    _headerStateNotifier.dispose();
    _controller
      ..removeListener(_adjustHeader)
      ..dispose();
    super.dispose();
  }

  List<Widget> _buildItems(
    WidgetRef ref, {
    required List<String> groupNames,
    required int columns,
    required Set<String> currentUnfoldSet,
    required ProxyCardType type,
    required String query,
  }) {
    final items = <Widget>[];
    final groupNameProxiesMap = <String, List<Proxy>>{};
    for (final groupName in groupNames) {
      final group = ref.watch(
        groupsProvider.select(
          (state) => state.getGroup(groupName),
        ),
      );
      if (group == null) {
        continue;
      }
      final sortedProxies = globalState.appController.getSortProxies(
        group.all
            .where((item) => item.name.toLowerCase().contains(query))
            .toList(),
        group.testUrl,
      );
      groupNameProxiesMap[groupName] = sortedProxies;
      final chunks = sortedProxies.chunks(columns);
      final rows = chunks
          .map<Widget>((proxies) {
            final children = proxies
                .map<Widget>(
                  (proxy) => Flexible(
                    flex: 1,
                    child: RepaintBoundary(
                      child: ProxyCard(
                        testUrl: group.testUrl,
                        type: type,
                        groupType: group.type,
                        key: ValueKey('$groupName.${proxy.name}'),
                        proxy: proxy,
                        groupName: groupName,
                      ),
                    ),
                  ),
                )
                .fill(
                  columns,
                  filler: (_) => const Flexible(
                    child: SizedBox(),
                  ),
                )
                .separated(
                  const SizedBox(
                    width: 8,
                  ),
                );

            return Row(
              children: children.toList(),
            );
          })
          .separated(
            SizedBox(
              height: type == ProxyCardType.oneline ? 4 : 8,
            ),
          )
          .toList();

      items.add(ProxyGroupCard(group: group, proxies: rows));
    }
    _lastGroupNameProxiesMap = groupNameProxiesMap;
    return items;
  }

  @override
  Widget build(BuildContext context) => Consumer(
      builder: (_, ref, __) {
        final state = ref.watch(proxiesListSelectorStateProvider);

        final groupsVersion = ref.watch(versionProvider);

        ref.watch(themeSettingProvider.select((state) => state.textScale));

        if (_lastGroupsVersion != groupsVersion ||
            !listEquals(_lastGroupNames, state.groupNames)) {
          _lastGroupsVersion = groupsVersion;
          _lastGroupNames = state.groupNames;

          _lastGroupNameProxiesMap.clear();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }

        if (state.groupNames.isEmpty) {
          return NullStatus(
            label: appLocalizations.nullTip(appLocalizations.proxies),
          );
        }
        final items = _buildItems(
          ref,
          groupNames: state.groupNames,
          currentUnfoldSet: state.currentUnfoldSet,
          columns: state.columns,
          type: state.proxyCardType,
          query: state.query,
        );
        return RepaintBoundary(
          child: CommonScrollBar(
            controller: _controller,
            child: Stack(
              children: [
              Positioned.fill(
                child: ScrollConfiguration(
                  behavior: HiddenBarScrollBehavior(),
                  child: FocusTraversalGroup(
                    policy: WidgetOrderTraversalPolicy(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      controller: _controller,
                      itemCount: items.length,
                      itemBuilder: (_, index) => items[index],
                    ),
                  ),
                ),
              ),
              ],
            ),
          ),
        );
      },
    );
}

class ProxyGroupCard extends StatefulWidget {

  const ProxyGroupCard({
    super.key,
    required this.group,
    required this.proxies,
  });
  final Group group;
  final List<Widget> proxies;

  @override
  State<ProxyGroupCard> createState() => _ProxyGroupCardState();
}

class _ProxyGroupCardState extends State<ProxyGroupCard>
    with AutomaticKeepAliveClientMixin {
  final _expansibleController = ExpansibleController();

  bool isLock = false;

  String get icon => widget.group.icon;

  String get groupName => widget.group.name;

  bool get isExpand => _expansibleController.isExpanded;


  @override
  void dispose() {
    _expansibleController.dispose();
    super.dispose();
  }

  void _toggleExpansion(Set<String> currentUnfoldSet) {
    final appController = globalState.appController;
    final unfoldSet = Set<String>.from(currentUnfoldSet);
    
    if (_expansibleController.isExpanded) {
      _expansibleController.collapse();
      unfoldSet.remove(groupName);
    } else {
      _expansibleController.expand();
      unfoldSet.add(groupName);
    }
    appController.updateCurrentUnfoldSet(unfoldSet);
  }

  Future<void> _delayTest() async {
    if (isLock) return;
    isLock = true;
    await delayTest(
      widget.group.all,
      widget.group.testUrl,
    );
    isLock = false;
  }

  Widget _buildIcon() => Consumer(
      builder: (_, ref, child) {
        final iconStyle = ref.watch(
          proxiesStyleSettingProvider.select(
            (state) => state.iconStyle,
          ),
        );
        final icon = ref.watch(proxiesStyleSettingProvider.select((state) {
          final iconMapEntryList = state.iconMap.entries.toList();
          final index = iconMapEntryList.indexWhere((item) {
            try {
              return RegExp(item.key).hasMatch(groupName);
            } catch (_) {
              return false;
            }
          });
          if (index != -1) {
            return iconMapEntryList[index].value;
          }
          return this.icon;
        }));
        return switch (iconStyle) {
          ProxiesIconStyle.icon => Container(
              margin: const EdgeInsets.only(
                right: 16,
              ),
              child: LayoutBuilder(
                builder: (_, constraints) => CommonTargetIcon(
                    src: icon,
                    size: 38,
                  ),
              ),
            ),
          ProxiesIconStyle.none => Container(),
        };
      },
    );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = context.colorScheme;
    return Consumer(
      builder: (_, ref, __) {
        final unfoldSet = ref.watch(unfoldSetProvider);
        final shouldExpand = unfoldSet.contains(groupName);
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (shouldExpand && !_expansibleController.isExpanded) {
            _expansibleController.expand();
          } else if (!shouldExpand && _expansibleController.isExpanded) {
            _expansibleController.collapse();
          }
        });
        
        return RepaintBoundary(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Expansible(
              controller: _expansibleController,
              headerBuilder: (context, animation) => GestureDetector(
                onTap: () => _toggleExpansion(unfoldSet),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow.opacity80,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10.0,
                    horizontal: 16.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          children: [
                            _buildIcon(),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    groupName,
                                    style: context.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Flexible(
                                    flex: 1,
                                    child: Consumer(
                                      builder: (_, ref, __) {
                                        final proxyName = ref
                                            .watch(getSelectedProxyNameProvider(groupName))
                                            .getSafeValue("");
                                        if (proxyName.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        return EmojiText(
                                          overflow: TextOverflow.ellipsis,
                                          proxyName,
                                          style: context.textTheme.labelMedium?.toLight,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          if (isExpand) ...[
                            IconButton(
                              onPressed: _delayTest,
                              visualDensity: VisualDensity.standard,
                              icon: const Icon(Icons.network_ping),
                            ),
                            const SizedBox(width: 6),
                          ] else
                            const SizedBox(width: 4),
                          IconButton.filledTonal(
                            onPressed: () => _toggleExpansion(unfoldSet),
                            icon: CommonExpandIcon(expand: isExpand),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              bodyBuilder: (context, animation) => RepaintBoundary(
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1.0,
                  child: FadeTransition(
                    opacity: animation,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(children: widget.proxies),
                    ),
                  ),
                ),
              ),
              expansibleBuilder: (context, header, body, animation) =>
                  Column(children: [header, body]),
            ),
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
