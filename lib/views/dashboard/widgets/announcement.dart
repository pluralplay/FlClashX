import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

final _linkPattern = RegExp(r'https?://[^\s<>"]+');

const _linkTrailing = '.,;:!?)';

/// What the subscription announced in its `announce` header, its links
/// opening after the external link prompt.
class AnnouncementCard extends ConsumerStatefulWidget {
  const AnnouncementCard({super.key});

  @override
  ConsumerState<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<AnnouncementCard> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _spanOf(String text, TextStyle style, Color linkColor) {
    _disposeRecognizers();
    final linkStyle = style.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
    final children = <InlineSpan>[];
    var at = 0;
    for (final match in _linkPattern.allMatches(text)) {
      var end = match.end;
      while (end > match.start && _linkTrailing.contains(text[end - 1])) {
        end--;
      }
      final url = text.substring(match.start, end);
      if (match.start > at) {
        children.add(EmojiText.spanOf(text.substring(at, match.start), style));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => dialogs.openUrl(url);
      _recognizers.add(recognizer);
      children.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      at = end;
    }
    if (at < text.length) {
      children.add(EmojiText.spanOf(text.substring(at), style));
    }
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final text = ref.watch(announcementProvider);
    if (text == null) {
      return const SizedBox.shrink();
    }
    final density = DashboardDensityScope.of(context);
    final mobile = !density.isDesktop;
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final style = AppTextStyle.subheadline
        .of(context)
        .copyWith(color: colorScheme.onSurface);
    return DashboardCard(
      semanticLabel: appLocalizations.announcement,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.info,
            title: appLocalizations.announcement,
          ),
          const SizedBox(height: 8),
          Text.rich(
            _spanOf(text, style, colorScheme.primary),
            maxLines: mobile ? null : 3,
            overflow: mobile ? null : TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
