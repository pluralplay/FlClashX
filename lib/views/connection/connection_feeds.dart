import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'connections.dart';
import 'requests.dart';

class ConnectionFeedsView extends ConsumerWidget {
  const ConnectionFeedsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(
      appSettingProvider.select((state) => state.requestFeed),
    );
    final appLocalizations = context.appLocalizations;
    final titleMenuItems = [
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
    return switch (feed) {
      RequestFeed.recent => RequestsView(titleMenuItems: titleMenuItems),
      RequestFeed.live => ConnectionsView(titleMenuItems: titleMenuItems),
    };
  }
}
