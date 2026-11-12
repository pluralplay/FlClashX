part of '../action.dart';

@Riverpod(keepAlive: true)
class ScriptsAction extends _$ScriptsAction {
  final _revisions = <int, int>{};
  final _downloads = <int, int>{};

  @visibleForTesting
  Future<String> Function(String url) download = (url) async =>
      (await request.getTextResponseForUrl(url)).data ?? '';

  @override
  void build() {}

  void putScript(Script script) {
    _bump(script.id);
    ref.read(scriptsProvider.notifier).put(script);
    _applyIfInUse(script.id);
  }

  /// Counts as a save before the file is touched, for a download to yield to.
  Future<void> saveScript(Script script, String content) async {
    _bump(script.id);
    putScript(await script.save(content));
  }

  Future<void> updateScript(Script script) async {
    final updatingKeys = ref.read(updatingKeysProvider.notifier);
    final operation = updatingKeys.start(script.updatingKey);
    final id = script.id;
    final revision = _revisions[id];
    final generation = _downloads[id] = (_downloads[id] ?? 0) + 1;
    final existed = _stored(id) != null;
    File? staged;
    try {
      final content = await download(script.url!);
      final path = await script.path;
      staged = File('$path.$generation.download');
      await staged.create(recursive: true);
      await staged.writeAsString(content);
      final current = _stored(id);
      if (_downloads[id] != generation ||
          _revisions[id] != revision ||
          (existed && current == null)) {
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

  void _bump(int id) => _revisions[id] = (_revisions[id] ?? 0) + 1;

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
