import 'dart:async';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';

import 'constant.dart';
import 'path.dart';

const logsDirectoryName = 'logs';

/// Appends every log line to `logs/FlClashX_<day>.log` under the app home,
/// starts `_<n>` files past [maxFileBytes] and drops days older than [keepDays].
class FileLogger {
  FileLogger({
    Future<String> Function()? directory,
    DateTime Function()? now,
    this.maxFileBytes = 10 * 1024 * 1024,
    this.keepDays = 10,
  }) : _directory = directory ?? _defaultDirectory,
       _now = now ?? DateTime.now;

  final Future<String> Function() _directory;
  final DateTime Function() _now;
  final int maxFileBytes;
  final int keepDays;

  static const _pendingLimit = 2000;

  final _pending = <String>[];
  Future<void> _drain = Future.value();
  bool _enabled = false;
  String? _day;
  File? _file;
  int _size = 0;

  static final _dayPattern = RegExp(
    r'^FlClashX_(\d{4}-\d{2}-\d{2})(?:_\d+)?\.log$',
  );

  static Future<String> _defaultDirectory() async =>
      join(await appPath.homeDirPath, logsDirectoryName);

  Future<String> get directoryPath async {
    final path = await _directory();
    await Directory(path).create(recursive: true);
    return path;
  }

  /// Lines queue until the app paths can be resolved, then land in order.
  void enable() {
    _enabled = true;
    _schedule();
  }

  void write(Log log) {
    _pending.add(
      '[${log.dateTime}] [${log.logLevel.name.toUpperCase()}] ${log.payload}',
    );
    if (_pending.length > _pendingLimit) {
      _pending.removeRange(0, _pending.length - _pendingLimit);
    }
    _schedule();
  }

  void _schedule() {
    if (!_enabled) {
      return;
    }
    _drain = _drain.then((_) => _flush()).catchError((_) {});
  }

  Future<void> flush() => _drain;

  Future<void> dispose() async {
    await _drain;
    _file = null;
    _day = null;
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) {
      return;
    }
    final lines = '${_pending.join('\n')}\n';
    _pending.clear();
    final file = await _target(lines.length);
    await file.writeAsString(lines, mode: FileMode.append, flush: true);
    _size += lines.length;
  }

  Future<File> _target(int incoming) async {
    final day = _dayOf(_now());
    final current = _file;
    if (current != null && _day == day && _size + incoming <= maxFileBytes) {
      return current;
    }
    final directory = await directoryPath;
    if (_day != day) {
      await _prune(directory, day);
    }
    _day = day;
    for (var index = 0; ; index++) {
      final name = index == 0
          ? '${appName}_$day.log'
          : '${appName}_${day}_$index.log';
      final file = File(join(directory, name));
      final size = await file.exists() ? await file.length() : 0;
      if (size + incoming <= maxFileBytes || size == 0) {
        _file = file;
        _size = size;
        return file;
      }
    }
  }

  Future<void> _prune(String directory, String today) async {
    final oldest = _parseDay(today).subtract(Duration(days: keepDays - 1));
    await for (final entity in Directory(directory).list(followLinks: false)) {
      final match = _dayPattern.firstMatch(basename(entity.path));
      if (entity is! File || match == null) {
        continue;
      }
      if (_parseDay(match.group(1)!).isBefore(oldest)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Another process may hold it; the next day's write tries again.
        }
      }
    }
  }

  static String _dayOf(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  static DateTime _parseDay(String day) => DateTime.parse(day);
}

final fileLogger = FileLogger();
