import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'setting.dart';
import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key, this.picker = false});

  /// Leaves the bar only its search and delay test, for picking a proxy from a
  /// sheet.
  final bool picker;

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> {
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();

  // The same instance on every build, so the bar changing with the current
  // group or its delay test leaves the page alone.
  late final _tabView = ProxiesTabView(key: _proxiesTabKey);
  bool _isTab = false;

  List<CommonPopupMenuItem> _buildMenuItems(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupMenuItem(
        glyph: AppGlyphs.sliders,
        label: appLocalizations.settings,
        onPressed: () {
          showSheet(
            context: context,
            builder: (_) {
              return CommonScaffold(
                body: const ProxiesSetting(),
                title: appLocalizations.settings,
              );
            },
          );
        },
      ),
    ];
  }

  IconButtonData? _buildPrimaryAction() {
    if (!_isTab) {
      return null;
    }
    final isDelayTesting = ref.watch(currentGroupDelayTestingProvider);
    return IconButtonData(
      glyph: AppGlyphs.bolt,
      onPressed: () {
        _proxiesTabKey.currentState?.delayTestCurrentGroup();
      },
      tooltip: context.appLocalizations.delayTest,
      isLoading: isDelayTesting,
    );
  }

  IconButtonData _buildFoldAllAction() {
    final allUnfolded = ref.watch(
      proxiesListStateProvider.select(
        (state) =>
            state.groups.isNotEmpty &&
            state.groups.every(
              (group) => state.currentUnfoldSet.contains(group.name),
            ),
      ),
    );
    final appLocalizations = context.appLocalizations;
    return IconButtonData(
      glyph: allUnfolded ? AppGlyphs.foldAll : AppGlyphs.unfoldAll,
      tooltip: allUnfolded
          ? appLocalizations.foldAllGroups
          : appLocalizations.unfoldAllGroups,
      onPressed: () => ref
          .read(proxiesActionProvider.notifier)
          .setShownGroupsUnfolded(!allUnfolded),
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.proxies).notifier).value = value;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.tab,
      ),
      (prev, next) {
        if (prev != next) {
          setState(() {
            _isTab = next;
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.type),
    );
    final isLoading = ref.watch(loadingProvider(LoadingTag.proxies));
    final picker = widget.picker;
    final primaryAction = _buildPrimaryAction();
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final isTestingAll = ref.watch(
      delayTestingGroupsProvider.select((state) => state.isNotEmpty),
    );
    final appLocalizations = context.appLocalizations;
    final barActions = [
      if (!picker) ...[
        if (ref.watch(globalModeAllowedProvider))
          IconButtonData(
            glyph: mode == Mode.global ? AppGlyphs.proxies : AppGlyphs.rules,
            tooltip:
                '${appLocalizations.outboundMode}: '
                '${mode == Mode.global ? appLocalizations.global : appLocalizations.rule}',
            onPressed: () => ref
                .read(setupActionProvider.notifier)
                .changeMode(mode == Mode.global ? Mode.rule : Mode.global),
          ),
        IconButtonData(
          glyph: AppGlyphs.bolt,
          tooltip: appLocalizations.delayTestAll,
          isLoading: isTestingAll,
          onPressed: isTestingAll
              ? null
              : () => ref
                    .read(proxiesActionProvider.notifier)
                    .delayTestAllGroups(),
        ),
      ],
      ?primaryAction,
    ];
    return CommonScaffold(
      isLoading: isLoading,
      resizeToAvoidBottomInset: false,
      // The picker sheet keeps the bar it had, close last.
      primaryAction: picker ? primaryAction : null,
      groupActions: !picker,
      searchActions: [?primaryAction],
      iconActions: [
        if (!picker) ...barActions,
        if (_isTab && !picker)
          IconButtonData(
            glyph: AppGlyphs.locate,
            onPressed: () {
              _proxiesTabKey.currentState?.scrollToGroupSelected();
            },
            tooltip: context.appLocalizations.scrollToSelected,
          ),
        if (!_isTab && !picker) _buildFoldAllAction(),
      ],
      menuItems: picker ? const [] : _buildMenuItems(context),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: switch (proxiesType) {
        ProxiesType.tab => _tabView,
        ProxiesType.list => const ProxiesListView(),
      },
    );
  }
}
