import 'dart:math';

import 'package:defer_pointer/defer_pointer.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/start_button.dart';


class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> with PageMixin {
  final key = GlobalKey<SuperGridState>();
  final _isEditNotifier = ValueNotifier<bool>(false);
  final _addedWidgetsNotifier = ValueNotifier<List<GridItem>>([]);

  @override
  void initState() {
    ref.listenManual(
      isCurrentPageProvider(PageLabel.dashboard),
      (prev, next) {
        if (prev != next && next == true) {
          initPageState();
        }
      },
      fireImmediately: true,
    );
    return super.initState();
  }

  @override
  void dispose() {
    _isEditNotifier.dispose();
    super.dispose();
  }

  @override
  Widget? get floatingActionButton => null; // Moved to bottom of body

  Widget _buildIsEdit(Widget Function(bool) builder) => ValueListenableBuilder(
      valueListenable: _isEditNotifier,
      builder: (_, isEdit, ___) => builder(isEdit),
    );

  @override
  List<Widget> get actions => [
        _buildIsEdit((isEdit) => isEdit
              ? ValueListenableBuilder(
                  valueListenable: _addedWidgetsNotifier,
                  builder: (_, addedChildren, child) {
                    if (addedChildren.isEmpty) {
                      return Container();
                    }
                    return child!;
                  },
                  child: IconButton(
                    onPressed: _showAddWidgetsModal,
                    icon: const Icon(
                      Icons.add_circle,
                    ),
                  ),
                )
              : const SizedBox()),
        Consumer(
          builder: (context, ref, child) {
            final denyEditing = ref.watch(currentProfileProvider
                .select((profile) => profile?.providerHeaders['flclashx-denywidgets']));

            if (denyEditing == 'true') {
              return const SizedBox.shrink();
            }

            return IconButton(
              icon: _buildIsEdit((isEdit) => isEdit
                    ? const Icon(Icons.save)
                    : const Icon(
                        Icons.edit,
                      )),
              onPressed: _handleUpdateIsEdit,
            );
          },
        ),
      ];

  void _showAddWidgetsModal() {
    showSheet(
      builder: (_, type) => ValueListenableBuilder(
          valueListenable: _addedWidgetsNotifier,
          builder: (_, value, __) => AdaptiveSheetScaffold(
              type: type,
              body: _AddDashboardWidgetModal(
                items: value,
                onAdd: (gridItem) {
                  key.currentState?.handleAdd(gridItem);
                },
              ),
              title: appLocalizations.add,
            ),
        ),
      context: context,
    );
  }

  void _handleUpdateIsEdit() {
    if (_isEditNotifier.value == true) {
      _handleSave();
    }
    _isEditNotifier.value = !_isEditNotifier.value;
  }

  void _handleSave() {
    final children = key.currentState?.children;
    if (children == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dashboardWidgets = children
          .map(
            DashboardWidget.getDashboardWidget,
          )
          .toList();
      ref.read(appSettingProvider.notifier).updateState(
            (state) => state.copyWith(dashboardWidgets: dashboardWidgets),
          );
    });
  }

  bool _isAllowedWidget(
    DashboardWidget item, {
    required bool globalModeEnabled,
    required bool hasAnnounceData,
    required bool hasServiceInfoData,
    required bool hasServerInfoData,
  }) {
    if (!item.platforms.contains(SupportPlatform.currentPlatform)) {
      return false;
    }
    
    if (!globalModeEnabled) {
      if (item == DashboardWidget.outboundMode || 
          item == DashboardWidget.outboundModeV2) {
        return false;
      }
    }
    
    if (item == DashboardWidget.announce && !hasAnnounceData) {
      return false;
    }
    if (item == DashboardWidget.serviceInfo && !hasServiceInfoData) {
      return false;
    }
    if (item == DashboardWidget.changeServerButton && !hasServerInfoData) {
      return false;
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardStateProvider);
    final globalModeEnabled = ref.watch(globalModeEnabledProvider);
    final hasAnnounce = ref.watch(hasAnnounceDataProvider);
    final hasServiceInfo = ref.watch(hasServiceInfoDataProvider);
    final hasServerInfo = ref.watch(hasServerInfoDataProvider);
    final columns = max(4 * ((dashboardState.viewWidth / 320).ceil()), 8);
    final spacing = 16.ap;
    
    bool isAllowed(DashboardWidget item) => _isAllowedWidget(
      item,
      globalModeEnabled: globalModeEnabled,
      hasAnnounceData: hasAnnounce,
      hasServiceInfoData: hasServiceInfo,
      hasServerInfoData: hasServerInfo,
    );
    
    final children = [
      ...dashboardState.dashboardWidgets
          .where(isAllowed)
          .map(
            (item) => item.widget,
          ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addedWidgetsNotifier.value = DashboardWidget.values
          .where(
            (item) => !children.contains(item.widget) && isAllowed(item),
          )
          .map((item) => item.widget)
          .toList();
    });
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16).copyWith(
                bottom: 16,
              ),
              child: _buildIsEdit((isEdit) => isEdit
                    ? SystemBackBlock(
                        child: CommonPopScope(
                          child: SuperGrid(
                            key: key,
                            crossAxisCount: columns,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            onUpdate: _handleSave,
                            children: [
                              ...dashboardState.dashboardWidgets
                                  .where(isAllowed)
                                  .map(
                                    (item) => item.widget,
                                  ),
                            ],
                          ),
                          onPop: () {
                            _handleUpdateIsEdit();
                            return false;
                          },
                        ),
                      )
                    : Grid(
                        crossAxisCount: columns,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        children: children,
                      )),
            ),
          ),
        ),
        // Start/Stop button at the bottom
        const StartButton(),
      ],
    );
  }
}

class _AddDashboardWidgetModal extends StatelessWidget {

  const _AddDashboardWidgetModal({
    required this.items,
    required this.onAdd,
  });
  final List<GridItem> items;
  final Function(GridItem item) onAdd;

  @override
  Widget build(BuildContext context) => DeferredPointerHandler(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Grid(
          crossAxisCount: 8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: items
              .map(
                (item) => item.wrap(
                  builder: (child) => _AddedContainer(
                      onAdd: () {
                        onAdd(item);
                      },
                      child: child,
                    ),
                ),
              )
              .toList(),
        ),
      ),
    );
}

class _AddedContainer extends StatefulWidget {

  const _AddedContainer({
    required this.child,
    required this.onAdd,
  });
  final Widget child;
  final VoidCallback onAdd;

  @override
  State<_AddedContainer> createState() => _AddedContainerState();
}

class _AddedContainerState extends State<_AddedContainer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(_AddedContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {}
  }

  Future<void> _handleAdd() async {
    widget.onAdd();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
      clipBehavior: Clip.none,
      children: [
        ActivateBox(
          child: widget.child,
        ),
        Positioned(
          top: -8,
          right: -8,
          child: DeferPointer(
            child: SizedBox(
              width: 24,
              height: 24,
              child: IconButton.filled(
                iconSize: 20,
                padding: const EdgeInsets.all(2),
                onPressed: _handleAdd,
                icon: const Icon(
                  Icons.add,
                ),
              ),
            ),
          ),
        )
      ],
    );
}
