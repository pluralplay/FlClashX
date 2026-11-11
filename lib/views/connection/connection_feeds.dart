import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'connections.dart';
import 'requests.dart';

class ConnectionFeedsView extends ConsumerStatefulWidget {
  const ConnectionFeedsView({super.key});

  @override
  ConsumerState<ConnectionFeedsView> createState() =>
      _ConnectionFeedsViewState();
}

class _ConnectionFeedsViewState extends ConsumerState<ConnectionFeedsView> {
  final _shown = <RequestFeed>{};

  List<CommonPopupMenuItem> _titleMenuItems(RequestFeed feed) {
    final appLocalizations = context.appLocalizations;
    return [
      for (final (option, label) in [
        (RequestFeed.recent, appLocalizations.recentRequests),
        (RequestFeed.live, appLocalizations.liveConnections),
      ])
        CommonPopupMenuItem(
          label: label,
          checked: option == feed,
          onPressed: () => ref
              .read(appSettingProvider.notifier)
              .update((state) => state.copyWith(requestFeed: option)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(
      appSettingProvider.select((state) => state.requestFeed),
    );
    _shown.add(feed);
    final pageActive = PageActivityScope.isActiveOf(context);
    final titleMenuItems = _titleMenuItems(feed);
    return IndexedStack(
      index: feed.index,
      children: [
        for (final option in RequestFeed.values)
          if (!_shown.contains(option))
            const SizedBox.shrink()
          else
            PageActivityScope(
              isActive: pageActive && option == feed,
              child: TickerMode(
                enabled: option == feed,
                child: ExcludeFocus(
                  excluding: option != feed,
                  child: switch (option) {
                    RequestFeed.recent => RequestsView(
                      titleMenuItems: titleMenuItems,
                    ),
                    RequestFeed.live => ConnectionsView(
                      titleMenuItems: titleMenuItems,
                    ),
                  },
                ),
              ),
            ),
      ],
    );
  }
}
