import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/profiles/custom/custom.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks for the link alone and adds the profile with the device headers on,
/// which the profile's own settings can turn off later. The page it was asked
/// from stays, so a profile added from the dashboard lands on it.
Future<void> addProfileByLink(BuildContext context, WidgetRef ref) async {
  final profilesAction = ref.read(profilesActionProvider.notifier);
  final link = await dialogs.showCommonDialog<String>(
    context: context,
    child: const AddProfileLinkDialog(),
  );
  if (link != null) {
    unawaited(profilesAction.addProfileFromLink(link, showProfiles: false));
  }
}

class AddProfileLinkDialog extends StatefulWidget {
  const AddProfileLinkDialog({super.key});

  @override
  State<AddProfileLinkDialog> createState() => _AddProfileLinkDialogState();
}

class _AddProfileLinkDialogState extends State<AddProfileLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isLink(String text) => text.isUrl || text.isShareLink;

  void _submit() {
    final link = _controller.text.trim();
    if (link.isEmpty) {
      return;
    }
    if (!_isLink(link)) {
      setState(() => _error = context.appLocalizations.invalidLinkTip);
      return;
    }
    Navigator.of(context).pop(link);
  }

  Future<void> _addFromClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted) {
      return;
    }
    if (text == null || !_isLink(text)) {
      setState(() => _error = context.appLocalizations.invalidLinkTip);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.addProfile,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: Text(appLocalizations.add),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            inputFormatters: TextInputLimits.limit(TextInputLimits.url),
            decoration: InputDecoration(
              hintText: appLocalizations.link,
              errorText: _error,
              errorMaxLines: 2,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          TonalButton(
            glyph: AppGlyphs.paste,
            label: appLocalizations.addFromClipboard,
            onPressed: () => unawaited(_addFromClipboard()),
          ),
        ],
      ),
    );
  }
}

/// The ways to add a profile, in a menu out of the control [builder] makes.
class AddProfileMenu extends ConsumerWidget {
  const AddProfileMenu({super.key, required this.builder});

  final Widget Function(PopupOpen open) builder;

  Future<void> _handleAddProfileFormFile(WidgetRef ref) async {
    unawaited(ref.read(profilesActionProvider.notifier).addProfileFormFile());
  }

  Future<void> _toScan(BuildContext context, WidgetRef ref) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    if (system.isDesktop) {
      unawaited(profilesAction.addProfileFormQrCode());
      return;
    }
    final url = await BaseNavigator.push(context, const ScanPage());
    if (url == null) {
      return;
    }
    if (context.mounted) {
      await whenRouteUncovered(context);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(profilesAction.addProfileFromLink(url));
    });
  }

  Future<void> _toSendFromPhone(WidgetRef ref) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    if (!(await app?.requestLocalNetworkPermission() ?? true)) {
      final appLocalizations = currentAppLocalizations;
      final res = await dialogs.showMessage(
        message: TextSpan(text: appLocalizations.sendFromPhonePermissionDenied),
        confirmText: appLocalizations.settings,
      );
      if (res == true) {
        await app?.openAppSettings();
      }
      return;
    }
    final link = await dialogs.showCommonDialog<String>(
      child: const _SendFromPhoneDialog(),
    );
    if (link == null) {
      return;
    }
    final appLocalizations = currentAppLocalizations;
    final confirmed = await dialogs.showMessage(
      title: appLocalizations.sendFromPhoneConfirmTitle,
      message: TextSpan(text: link),
      confirmText: appLocalizations.import,
    );
    if (confirmed == true) {
      unawaited(profilesAction.addProfileFromLink(link));
    }
  }

  void _toAddCustom(BuildContext context, WidgetRef ref) {
    final profileId = ref
        .read(profilesActionProvider.notifier)
        .addCustomProfile(context.appLocalizations.unnamed);
    unawaited(
      BaseNavigator.push(
        context,
        CustomProfileView(profileId: profileId, isNew: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    return CommonPopupBox(
      targetBuilder: builder,
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          CommonPopupMenuItem(
            glyph: AppGlyphs.qrCode,
            label: appLocalizations.qrcode,
            onPressed: () => _toScan(context, ref),
          ),
          CommonPopupMenuItem(
            glyph: AppGlyphs.importFile,
            label: appLocalizations.file,
            onPressed: () => _handleAddProfileFormFile(ref),
          ),
          CommonPopupMenuItem(
            glyph: AppGlyphs.cloudDownload,
            label: appLocalizations.link,
            onPressed: () => addProfileByLink(context, ref),
          ),
          if (system.isTV)
            CommonPopupMenuItem(
              glyph: AppGlyphs.devices,
              label: appLocalizations.sendFromPhone,
              onPressed: () => _toSendFromPhone(ref),
            ),
          CommonPopupMenuItem(
            section: const CommonPopupMenuSection(),
            glyph: AppGlyphs.customize,
            label: appLocalizations.customProfile,
            onPressed: () => _toAddCustom(context, ref),
          ),
        ],
      ),
    );
  }
}

class _SendFromPhoneDialog extends StatefulWidget {
  const _SendFromPhoneDialog();

  @override
  State<_SendFromPhoneDialog> createState() => _SendFromPhoneDialogState();
}

class _SendFromPhoneDialogState extends State<_SendFromPhoneDialog> {
  LinkReceiver? _receiver;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final appLocalizations = currentAppLocalizations;
    final receiver = await LinkReceiver.start((
      title: appLocalizations.sendFromPhonePageTitle,
      hint: appLocalizations.sendFromPhonePageHint,
      send: appLocalizations.send,
      sent: appLocalizations.sendFromPhonePageSent,
      invalid: appLocalizations.invalidLinkTip,
    )).catchError((Object _) => null);
    if (!mounted) {
      unawaited(receiver?.close());
      return;
    }
    setState(() {
      _receiver = receiver;
      _failed = receiver == null;
    });
    final link = await receiver?.link;
    if (link != null && mounted) {
      Navigator.of(context).pop(link);
    }
  }

  @override
  void dispose() {
    unawaited(_receiver?.close());
    super.dispose();
  }

  Widget _buildContent(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    if (_failed) {
      return Text(
        appLocalizations.sendFromPhoneNoNetwork,
        textAlign: TextAlign.center,
      );
    }
    final address = _receiver?.address.toString();
    if (address == null) {
      return const SizedBox.square(
        dimension: 96,
        child: Center(child: CommonCircleLoading()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        QrCodeView(data: address, size: 200),
        SelectableText(address, textAlign: TextAlign.center),
        Text(appLocalizations.sendFromPhoneTip, textAlign: TextAlign.center),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.appLocalizations.sendFromPhone,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.appLocalizations.cancel),
        ),
      ],
      child: _buildContent(context),
    );
  }
}
