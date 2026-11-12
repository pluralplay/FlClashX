import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/selection_mark.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _testUrl = 'https://example.com/generate_204';
const _pinned = 'A pinned proxy with a name far too long for one line';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pinned one-line fallback card keeps the delay and the pin '
      'on the name line', (tester) async {
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        delayDataSourceProvider.overrideWithBuild(
          (_, _) => {
            _testUrl: {_pinned: 123},
          },
        ),
        proxyNameProvider('group').overrideWithValue(_pinned),
        selectedProxyNameProvider('group').overrideWithValue(_pinned),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          homeBuilder: (child) => Scaffold(body: child),
          child: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (_) => SizedBox(
                width: 220,
                height: getItemHeight(ProxyCardType.oneline),
                child: const ProxyCard(
                  groupName: 'group',
                  testUrl: _testUrl,
                  proxy: Proxy(name: _pinned, type: 'Shadowsocks'),
                  groupType: GroupType.Fallback,
                  type: ProxyCardType.oneline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final delay = tester.getRect(find.text('123 ms'));
    final badge = tester.getRect(find.byType(SelectionBadge));
    final card = tester.getRect(find.byType(ProxyCard));
    expect(badge.left, greaterThanOrEqualTo(delay.right));
    expect(badge.right, lessThanOrEqualTo(card.right));
    expect(delay.center.dy, moreOrLessEquals(badge.center.dy, epsilon: 1));
    expect(badge.top, greaterThanOrEqualTo(card.top));
    expect(badge.bottom, lessThanOrEqualTo(card.bottom));
  });
}
