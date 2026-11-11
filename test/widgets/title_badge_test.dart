import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('a row keeps its title badge while it opens its page', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestApp(
        child: ViewScope(
          isMobile: true,
          child: Scaffold(
            body: TitleBadge(
              badge: const Text('badge'),
              child: ListItem.open(
                title: const Text('Row'),
                widget: const Text('Page'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('badge'), findsOneWidget);

    await tester.tap(find.text('Row'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('badge'), findsWidgets);
  });
}
