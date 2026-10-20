import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True only after "I agree"; any other way out declines.
Future<bool> requestDisclaimerConsent() async {
  return await BaseNavigator.push<bool>(
        rootNavigatorKey.currentContext!,
        const DisclaimerView(requireConsent: true),
      ) ??
      false;
}

class DisclaimerView extends StatelessWidget {
  final bool requireConsent;

  const DisclaimerView({super.key, this.requireConsent = false});

  static const _maxContentWidth = 720.0;

  List<({String title, String content})> _terms(AppLocalizations l) => [
    (title: l.disclaimerSoftwareTitle, content: l.disclaimerSoftwareContent),
    (
      title: l.disclaimerResponsibilityTitle,
      content: l.disclaimerResponsibilityContent,
    ),
    (title: l.disclaimerPrivacyTitle, content: l.disclaimerPrivacyContent),
    (title: l.disclaimerLicenseTitle, content: l.disclaimerLicenseContent),
  ];

  static const _mobileGutter = 16.0;
  static const _desktopGutter = 24.0;
  static const _desktopTopPadding = 48.0;

  ListView _buildBody({
    required EdgeInsets padding,
    required List<Widget> children,
  }) {
    return ListView(
      padding: padding,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final terms = _buildTerms(appLocalizations);
    final body = _buildBody(
      padding: const EdgeInsets.symmetric(
        horizontal: _mobileGutter,
      ).copyWith(top: context.contentTopPadding, bottom: 32),
      children: terms,
    );
    if (!requireConsent) {
      return CommonScaffold(title: appLocalizations.disclaimer, body: body);
    }
    return Consumer(
      builder: (context, ref, _) {
        if (ref.watch(isMobileViewProvider)) {
          return CommonScaffold(
            title: appLocalizations.disclaimer,
            body: _ConsentLayout(
              maxWidth: _maxContentWidth,
              gutter: _mobileGutter,
              compact: true,
              child: body,
            ),
          );
        }
        return Scaffold(
          body: SafeArea(
            child: _ConsentLayout(
              maxWidth: _maxContentWidth,
              gutter: _desktopGutter,
              compact: false,
              child: _buildBody(
                padding: const EdgeInsets.fromLTRB(
                  _desktopGutter,
                  _desktopTopPadding,
                  _desktopGutter,
                  32,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      appLocalizations.disclaimer,
                      style: AppTextStyle.title2.of(context, emphasized: true),
                    ),
                  ),
                  ...terms,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTerms(AppLocalizations appLocalizations) {
    return [
      _DisclaimerIntro(text: appLocalizations.disclaimerDesc),
      for (final (index, term) in _terms(appLocalizations).indexed)
        _DisclaimerTerm(
          index: index + 1,
          title: term.title,
          content: term.content,
        ),
    ];
  }
}

class _DisclaimerIntro extends StatelessWidget {
  final String text;

  const _DisclaimerIntro({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.xl,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlyphIcon(AppGlyphs.gavel, size: 28, color: colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclaimerTerm extends StatelessWidget {
  final int index;
  final String title;
  final String content;

  const _DisclaimerTerm({
    required this.index,
    required this.title,
    required this.content,
  });

  static const _badgeSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: context.raisedSurfaceLevel.colorOf(colorScheme),
                  shape: AppShape.full,
                ),
                child: SizedBox.square(
                  dimension: _badgeSize,
                  child: Center(
                    child: Text(
                      '$index',
                      style: AppTextStyle.caption1
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: AppTextStyle.headline.of(context)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TermParagraphs(content),
        ],
      ),
    );
  }
}

class _TermParagraphs extends StatelessWidget {
  final String text;

  const _TermParagraphs(this.text);

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.subheadline
        .of(context)
        .copyWith(color: context.colorScheme.onSurfaceVariant, height: 1.6);
    final paragraphs = text.split('\n\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, paragraph) in paragraphs.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
            child: Text(paragraph, style: style),
          ),
      ],
    );
  }
}

class _ConsentLayout extends StatelessWidget {
  final double maxWidth;
  final double gutter;
  final bool compact;
  final Widget child;

  const _ConsentLayout({
    required this.maxWidth,
    required this.gutter,
    required this.compact,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child),
        _ConsentBar(maxWidth: maxWidth, gutter: gutter, compact: compact),
      ],
    );
  }
}

class _ConsentBar extends StatelessWidget {
  final double maxWidth;
  final double gutter;
  final bool compact;

  const _ConsentBar({
    required this.maxWidth,
    required this.gutter,
    required this.compact,
  });

  Widget _buildExitButton(BuildContext context) {
    return ElasticButton(
      child: OutlinedButton(
        onPressed: () {
          Navigator.of(context).pop(false);
        },
        child: Text(context.appLocalizations.exit),
      ),
    );
  }

  Widget _buildAgreeButton(BuildContext context) {
    return ElasticButton(
      child: FilledButton(
        onPressed: () {
          Navigator.of(context).pop(true);
        },
        child: Text(context.appLocalizations.agree),
      ),
    );
  }

  Widget _buildCompactActions(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildExitButton(context)),
        const SizedBox(width: 12),
        Expanded(child: _buildAgreeButton(context)),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        _buildExitButton(context),
        const SizedBox(width: 12),
        _buildAgreeButton(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SurfaceLevel.page.colorOf(context.colorScheme),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth + gutter * 2),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 12),
              child: compact
                  ? _buildCompactActions(context)
                  : _buildActions(context),
            ),
          ),
        ),
      ),
    );
  }
}
