import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/update/asset.dart';
import 'package:fl_clash/features/update/controller.dart';
import 'package:fl_clash/features/update/platform.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateController Function() createController;
  final InlineSpan notes;

  /// Offered in place of a plain close on a reminder the app raised itself.
  final VoidCallback? onStopReminding;
  final VoidCallback onOpenReleasePage;

  const UpdateDialog({
    super.key,
    required this.createController,
    required this.notes,
    required this.onOpenReleasePage,
    this.onStopReminding,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  late final UpdateController _controller = widget.createController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  Widget _action(String label, VoidCallback onPressed) =>
      TextButton(onPressed: onPressed, child: Text(label));

  List<Widget> _actions(AppLocalizations l10n, UpdateState state) {
    final close = _action(l10n.close, _close);
    final github = _action(l10n.updateViewOnGitHub, widget.onOpenReleasePage);
    return switch (state.phase) {
      UpdatePhase.idle => [
        if (widget.onStopReminding case final stop?)
          _action(l10n.noLongerRemind, () {
            stop();
            _close();
          })
        else
          close,
        github,
        if (_controller.canDownload)
          _action(l10n.goDownload, _controller.download),
      ],
      UpdatePhase.downloading ||
      UpdatePhase.verifying => [_action(l10n.cancel, _controller.cancel)],
      UpdatePhase.ready => [
        close,
        _action(l10n.updateInstall, _controller.install),
      ],
      UpdatePhase.installing => const [],
      UpdatePhase.done => [close],
      UpdatePhase.failed => [
        close,
        github,
        _action(l10n.retry, _controller.download),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return ValueListenableBuilder<UpdateState>(
      valueListenable: _controller,
      builder: (context, state, _) => PopScope(
        canPop: state.phase != UpdatePhase.installing,
        child: CommonDialog(
          title: l10n.discoverNewVersion,
          actions: _actions(l10n, state),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText.rich(
                TextSpan(children: [widget.notes]),
                style: const TextStyle(overflow: TextOverflow.visible),
              ),
              _UpdateStatus(
                state: state,
                kind: _controller.platform.target.kind,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateStatus extends StatelessWidget {
  final UpdateState state;
  final UpdateInstallKind kind;

  const _UpdateStatus({required this.state, required this.kind});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final error = state.error;
    final double? progress;
    final String? text;
    switch (state.phase) {
      case UpdatePhase.idle:
        progress = null;
        text = switch (kind) {
          UpdateInstallKind.packageManager => l10n.updatePackageManager,
          UpdateInstallKind.unsupported => l10n.updateUnsupported,
          _ => null,
        };
      case UpdatePhase.downloading:
        final total = state.total;
        progress = total == null || total == 0 ? null : state.received / total;
        text = total == null
            ? state.received.traffic.show
            : l10n.updateDownloadProgress(
                state.received.traffic.show,
                total.traffic.show,
                ((progress ?? 0) * 100).floor(),
              );
      case UpdatePhase.verifying:
        progress = null;
        text = l10n.updateVerifying;
      case UpdatePhase.installing:
        progress = null;
        text = l10n.updateInstalling;
      case UpdatePhase.ready:
        progress = null;
        text = error == null ? l10n.updateReady : null;
      case UpdatePhase.done:
        progress = null;
        text = switch (state.result) {
          UpdateInstallResult.openedImage => l10n.updateOpenedImage,
          UpdateInstallResult.handedOff => l10n.updateHandedOff,
          _ => l10n.updateExiting,
        };
      case UpdatePhase.failed:
        progress = null;
        text = null;
    }
    final working = state.isWorking;
    if (text == null && error == null && !working) {
      return const SizedBox.shrink();
    }
    final colorScheme = context.colorScheme;
    final style = AppTextStyle.subheadline.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (working) LinearProgressIndicator(minHeight: 4, value: progress),
          if (text != null) Text(text, style: style),
          if (error != null) ...[
            Text(
              updateErrorText(l10n, error.kind),
              style: style.copyWith(color: colorScheme.error),
            ),
            if (error.detail != null && _showsDetail(error.kind))
              Text(
                error.detail!,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
          ],
        ],
      ),
    );
  }

  bool _showsDetail(UpdateErrorKind kind) =>
      kind == UpdateErrorKind.network || kind == UpdateErrorKind.installFailed;
}

String updateErrorText(AppLocalizations l10n, UpdateErrorKind kind) =>
    switch (kind) {
      UpdateErrorKind.noAsset => l10n.updateErrorNoAsset,
      UpdateErrorKind.noChecksum => l10n.updateErrorNoChecksum,
      UpdateErrorKind.untrustedHost => l10n.updateErrorUntrustedHost,
      UpdateErrorKind.tooLarge => l10n.updateErrorTooLarge,
      UpdateErrorKind.incomplete => l10n.updateErrorIncomplete,
      UpdateErrorKind.network => l10n.updateErrorNetwork,
      UpdateErrorKind.checksumMismatch => l10n.updateErrorChecksum,
      UpdateErrorKind.identityMismatch => l10n.updateErrorIdentity,
      UpdateErrorKind.notNewer => l10n.updateErrorNotNewer,
      UpdateErrorKind.busy => l10n.updateErrorBusy,
      UpdateErrorKind.safeMode => l10n.updateErrorSafeMode,
      UpdateErrorKind.installPermission => l10n.updateErrorPermission,
      UpdateErrorKind.installFailed => l10n.updateErrorInstall,
    };
