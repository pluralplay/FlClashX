import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

var _attempt = 0;

/// Asked before the store opens, so it stands alone like the init error app.
Future<bool> askStableImportRetry() async {
  final choice = Completer<bool>();
  runApp(StableImportApp(key: ValueKey(_attempt++), onChoice: choice.complete));
  await window?.showBeforeInit();
  return choice.future;
}

class StableImportApp extends StatelessWidget {
  const StableImportApp({super.key, required this.onChoice});

  final ValueChanged<bool> onChoice;

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: seededColorScheme(
        seedColor: const Color(defaultPrimaryColor),
        brightness: brightness,
      ),
    ).withAppShapes.withAppSurfaces;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appName,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: StableImportScreen(onChoice: onChoice),
    );
  }
}

class StableImportScreen extends StatefulWidget {
  const StableImportScreen({super.key, required this.onChoice});

  final ValueChanged<bool> onChoice;

  @override
  State<StableImportScreen> createState() => _StableImportScreenState();
}

class _StableImportScreenState extends State<StableImportScreen> {
  var _chosen = false;

  void _choose(bool retry) {
    if (_chosen) {
      return;
    }
    setState(() {
      _chosen = true;
    });
    widget.onChoice(retry);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: colorScheme.primaryContainer,
                      shape: AppShape.full,
                    ),
                    child: SizedBox.square(
                      dimension: 56,
                      child: Center(
                        child: GlyphIcon(
                          AppGlyphs.importFile,
                          size: 28,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    appLocalizations.stableImportTitle,
                    style: AppTextStyle.title2.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appLocalizations.stableImportTip,
                    style: AppTextStyle.body
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _chosen ? null : () => _choose(true),
                        child: Text(appLocalizations.stableImportRetry),
                      ),
                      TextButton(
                        onPressed: _chosen ? null : () => _choose(false),
                        child: Text(appLocalizations.stableImportSkip),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
