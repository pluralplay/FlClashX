part of '../general.dart';

const _minPort = 1024;
const _maxPort = 49151;

class _PortField {
  final TextEditingController controller;
  final String Function(AppLocalizations appLocalizations) label;
  final String settingKey;
  final int Function(PatchClashConfig config) select;
  final bool allowDisabled;

  const _PortField({
    required this.controller,
    required this.label,
    required this.settingKey,
    required this.select,
    this.allowDisabled = true,
  });
}

class _PortForm extends ConsumerStatefulWidget {
  const _PortForm();

  @override
  ConsumerState<_PortForm> createState() => _PortFormState();
}

class _PortFormState extends ConsumerState<_PortForm> {
  late final TextEditingController _mixedPortController;
  late final TextEditingController _portController;
  late final TextEditingController _socksPortController;
  late final TextEditingController _redirPortController;
  late final TextEditingController _tProxyPortController;
  late final List<_PortField> _fields;

  @override
  void initState() {
    super.initState();
    final ports = ref.read(
      patchClashConfigProvider.select((state) {
        return (
          mixed: state.mixedPort,
          http: state.port,
          socks: state.socksPort,
          redir: state.redirPort,
          tproxy: state.tproxyPort,
        );
      }),
    );
    _mixedPortController = TextEditingController(text: ports.mixed.toString());
    _portController = TextEditingController(text: ports.http.toString());
    _socksPortController = TextEditingController(text: ports.socks.toString());
    _redirPortController = TextEditingController(text: ports.redir.toString());
    _tProxyPortController = TextEditingController(
      text: ports.tproxy.toString(),
    );
    _fields = [
      _PortField(
        controller: _mixedPortController,
        settingKey: 'clash.mixed-port',
        select: (config) => config.mixedPort,
        label: (appLocalizations) => appLocalizations.mixedPort,
        allowDisabled: false,
      ),
      _PortField(
        controller: _portController,
        settingKey: 'clash.port',
        select: (config) => config.port,
        label: (appLocalizations) => appLocalizations.port,
      ),
      _PortField(
        controller: _socksPortController,
        settingKey: 'clash.socks-port',
        select: (config) => config.socksPort,
        label: (appLocalizations) => appLocalizations.socksPort,
      ),
      _PortField(
        controller: _redirPortController,
        settingKey: 'clash.redir-port',
        select: (config) => config.redirPort,
        label: (appLocalizations) => appLocalizations.redirPort,
      ),
      _PortField(
        controller: _tProxyPortController,
        settingKey: 'clash.tproxy-port',
        select: (config) => config.tproxyPort,
        label: (appLocalizations) => appLocalizations.tproxyPort,
      ),
    ];
  }

  Future<void> _handleReset() async {
    final res = await dialogs.showMessage(
      message: TextSpan(text: context.appLocalizations.resetTip),
      destructive: true,
      confirmText: context.appLocalizations.reset,
    );
    if (res != true) {
      return;
    }
    bool locked(String key) => ref.read(settingLockedProvider(key));
    const defaults = PatchClashConfig();
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(
            mixedPort: locked('clash.mixed-port')
                ? state.mixedPort
                : defaults.mixedPort,
            port: locked('clash.port') ? state.port : defaults.port,
            socksPort: locked('clash.socks-port')
                ? state.socksPort
                : defaults.socksPort,
            redirPort: locked('clash.redir-port')
                ? state.redirPort
                : defaults.redirPort,
            tproxyPort: locked('clash.tproxy-port')
                ? state.tproxyPort
                : defaults.tproxyPort,
          ),
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// What a save writes for [field]: a locked port keeps the subscription's.
  String _textOf(_PortField field) =>
      ref.read(settingLockedProvider(field.settingKey))
      ? '${field.select(ref.read(patchClashConfigProvider))}'
      : field.controller.text;

  Map<_PortField, String> _issues(AppLocalizations appLocalizations) {
    return {
      for (final field in _fields)
        field: ?validatePort(field, _textOf(field), appLocalizations),
    };
  }

  void _handleUpdate() {
    if (_issues(context.appLocalizations).isNotEmpty) {
      return;
    }
    final ports = [for (final field in _fields) int.parse(_textOf(field))];
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(
            mixedPort: ports[0],
            port: ports[1],
            socksPort: ports[2],
            redirPort: ports[3],
            tproxyPort: ports[4],
          ),
        );
    Navigator.of(context).pop();
  }

  @visibleForTesting
  String? validatePort(
    _PortField field,
    String? value,
    AppLocalizations appLocalizations,
  ) {
    final label = field.label(appLocalizations);
    if (value == null || value.isEmpty) {
      return appLocalizations.emptyTip(label);
    }
    final port = int.tryParse(value);
    if (port == null) {
      return appLocalizations.numberTip(label);
    }
    if (field.allowDisabled && port == 0) {
      return null;
    }
    if (port < _minPort || port > _maxPort) {
      return appLocalizations.portTip(label);
    }
    final others = _fields
        .where((item) => item != field)
        .map((item) => int.tryParse(_textOf(item).trim()));
    if (others.contains(port)) {
      return appLocalizations.portConflictTip;
    }
    return null;
  }

  @override
  void dispose() {
    _mixedPortController.dispose();
    _portController.dispose();
    _socksPortController.dispose();
    _redirPortController.dispose();
    _tProxyPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    for (final field in _fields) {
      ref.watch(settingLockedProvider(field.settingKey));
      ref.watch(patchClashConfigProvider.select(field.select));
    }
    final issues = _issues(appLocalizations);
    return FormPage(
      title: appLocalizations.port,
      onSave: _handleUpdate,
      error: issues.values.firstOrNull,
      children: [
        generateSection(
          items: [
            for (final field in _fields)
              ManagedSetting(
                settingKey: field.settingKey,
                child: FormRow(
                  title: field.label(appLocalizations),
                  invalid: issues.containsKey(field),
                  trailing: FormRowTextField(
                    controller: field.controller,
                    hintText: appLocalizations.required,
                    keyboardType: TextInputType.number,
                    textInputAction: field == _fields.last
                        ? TextInputAction.done
                        : TextInputAction.next,
                    inputFormatters: TextInputLimits.digitsOnly(
                      TextInputLimits.port,
                    ),
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) => _handleUpdate(),
                  ),
                ),
              ),
          ],
        ),
        const ListSectionGap(),
        generateSection(
          items: [
            FormRow(title: appLocalizations.reset, onPressed: _handleReset),
          ],
        ),
      ],
    );
  }
}
