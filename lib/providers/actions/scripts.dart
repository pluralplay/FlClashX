part of '../action.dart';

@Riverpod(keepAlive: true)
class ScriptsAction extends _$ScriptsAction {
  final _revisions = <int, int>{};

  @visibleForTesting
  Future<String> Function(String url) download = (url) async =>
      (await request.getTextResponseForUrl(url)).data ?? '';

  @override
  void build() {}

  void putScript(Script script) {
    _revisions[script.id] = (_revisions[script.id] ?? 0) + 1;
    ref.read(scriptsProvider.notifier).put(script);
    _applyIfInUse(script.id);
  }

  /// A download a save or a delete overtook is dropped, not written.
  Future<void> updateScript(Script script) async {
    final updatingKeys = ref.read(updatingKeysProvider.notifier);
    final operation = updatingKeys.start(script.updatingKey);
    final revision = _revisions[script.id];
    final existed = _stored(script.id) != null;
    File? staged;
    try {
      final content = await download(script.url!);
      final path = await script.path;
      staged = File('$path.download');
      await staged.create(recursive: true);
      await staged.writeAsString(content);
      final current = _stored(script.id);
      if (_revisions[script.id] != revision || (existed && current == null)) {
        return;
      }
      staged.renameSync(path);
      staged = null;
      putScript(
        (current ?? script).copyWith(
          url: script.url,
          lastUpdateTime: DateTime.now(),
        ),
      );
    } finally {
      if (staged != null && staged.existsSync()) {
        staged.deleteSync();
      }
      updatingKeys.stop(script.updatingKey, operation);
    }
  }

  Script? _stored(int id) => ref
      .read(scriptsProvider)
      .value
      ?.where((script) => script.id == id)
      .firstOrNull;

  void _applyIfInUse(int scriptId) {
    final profile = ref.read(currentProfileProvider);
    if (profile?.extendType != ExtendType.script ||
        profile?.scriptId != scriptId) {
      return;
    }
    ref.read(setupActionProvider.notifier).applyProfileDebounce(silence: true);
  }
}
