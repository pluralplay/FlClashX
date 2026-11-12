part of '../action.dart';

@Riverpod(keepAlive: true)
class ScriptsAction extends _$ScriptsAction {
  final _revisions = <int, int>{};
  final _downloads = <int, int>{};
  final _fileLocks = <int, Future<void>>{};

  @visibleForTesting
  Future<String> Function(String url) download = (url) async =>
      (await request.getTextResponseForUrl(url)).data ?? '';

  @visibleForTesting
  Future<Script> Function(Script script, String content) write =
      (script, content) => script.save(content);

  @override
  void build() {}

  void putScript(Script script) {
    _bump(script.id);
    ref.read(scriptsProvider.notifier).put(script);
    _applyIfInUse(script.id);
  }

  /// Counts as a save before the file is touched, for a download to yield to.
  Future<void> saveScript(Script script, String content) {
    _bump(script.id);
    return _withFile(
      script.id,
      () async => putScript(await write(script, content)),
    );
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
      final ready = staged = File('$path.$generation.download');
      await ready.create(recursive: true);
      await ready.writeAsString(content);
      await _withFile(id, () async {
        final current = _stored(id);
        if (_downloads[id] != generation ||
            _revisions[id] != revision ||
            (existed && current == null)) {
          return;
        }
        ready.renameSync(path);
        putScript(
          (current ?? script).copyWith(
            url: script.url,
            lastUpdateTime: DateTime.now(),
          ),
        );
      });
    } finally {
      if (staged != null && staged.existsSync()) {
        staged.deleteSync();
      }
      updatingKeys.stop(script.updatingKey, operation);
    }
  }

  /// A rename during a save's write would drop the save's bytes.
  Future<void> _withFile(int id, Future<void> Function() run) {
    final turn = (_fileLocks[id] ?? Future<void>.value()).then((_) => run());
    final settled = turn.then<void>((_) {}, onError: (Object _) {});
    _fileLocks[id] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_fileLocks[id], settled)) {
          _fileLocks.remove(id);
        }
      }),
    );
    return turn;
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
