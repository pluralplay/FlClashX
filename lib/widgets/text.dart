import 'package:emoji_regex/emoji_regex.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter/material.dart';

import '../state.dart';

class TooltipText extends StatelessWidget {

  const TooltipText({
    super.key,
    required this.text,
  });
  final Text text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, container) {
        final maxWidth = container.maxWidth;
        final size = globalState.measure.computeTextSize(
          text,
        );
        if (maxWidth < size.width) {
          return Tooltip(
            preferBelow: false,
            message: text.data,
            child: text,
          );
        }
        return text;
      },
    );
}

class EmojiText extends StatelessWidget {

  const EmojiText(
    this.text, {
    super.key,
    this.maxLines,
    this.overflow,
    this.style,
  });
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  List<TextSpan> _buildTextSpans(String emojis) {
    final spans = <TextSpan>[];
    final matches = emojiRegex().allMatches(text);

    var lastMatchEnd = 0;
    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
              text: text.substring(lastMatchEnd, match.start), style: style),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: style?.copyWith(
            fontFamily: FontFamily.twEmoji.value,
          ),
        ),
      );
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastMatchEnd),
          style: style,
        ),
      );
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) => RichText(
      textScaler: MediaQuery.of(context).textScaler,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        children: _buildTextSpans(text),
      ),
    );
}
