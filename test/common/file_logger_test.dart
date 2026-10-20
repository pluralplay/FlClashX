import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('flclash-file-logger-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Log log(String payload, [LogLevel level = LogLevel.info]) =>
      Log(payload: payload, logLevel: level, dateTime: '12:00:00');

  FileLogger logger({DateTime? day, int maxFileBytes = 10 * 1024 * 1024}) =>
      FileLogger(
        directory: () async => join(root.path, 'logs'),
        now: () => day ?? DateTime(2026, 10, 20, 15),
        maxFileBytes: maxFileBytes,
      )..enable();

  test('appends each line to the day file with its level', () async {
    final sink = logger();

    sink.write(log('started'));
    sink.write(log('core down', LogLevel.error));
    await sink.flush();

    final file = File(join(root.path, 'logs', 'FlClashX_2026-10-20.log'));
    expect(file.readAsLinesSync(), [
      '[12:00:00] [INFO] started',
      '[12:00:00] [ERROR] core down',
    ]);
  });

  test('a full file is followed by a numbered one', () async {
    final sink = logger(maxFileBytes: 90);

    for (var i = 0; i < 5; i++) {
      sink.write(log('line number $i padded out'));
      await sink.flush();
    }

    final names = Directory(
      join(root.path, 'logs'),
    ).listSync().map((entity) => basename(entity.path)).toList()..sort();
    expect(names, [
      'FlClashX_2026-10-20.log',
      'FlClashX_2026-10-20_1.log',
      'FlClashX_2026-10-20_2.log',
    ]);
    for (final name in names) {
      expect(File(join(root.path, 'logs', name)).lengthSync(), lessThan(91));
    }
  });

  test(
    'a new day drops files older than ten days and keeps the rest',
    () async {
      final logs = Directory(join(root.path, 'logs'))
        ..createSync(recursive: true);
      for (final name in [
        'FlClashX_2026-10-10.log',
        'FlClashX_2026-10-10_1.log',
        'FlClashX_2026-10-11.log',
        'FlClashX_2026-10-19.log',
        'notes.txt',
      ]) {
        File(join(logs.path, name)).writeAsStringSync('x');
      }
      final sink = logger();

      sink.write(log('today'));
      await sink.flush();

      final names = logs.listSync().map((e) => basename(e.path)).toList()
        ..sort();
      expect(names, [
        'FlClashX_2026-10-11.log',
        'FlClashX_2026-10-19.log',
        'FlClashX_2026-10-20.log',
        'notes.txt',
      ]);
    },
  );

  test('nothing touches the disk until the logger is enabled', () async {
    final sink = FileLogger(
      directory: () async => join(root.path, 'logs'),
      now: () => DateTime(2026, 10, 20),
    );
    sink.write(log('early'));
    await sink.flush();
    expect(Directory(join(root.path, 'logs')).existsSync(), isFalse);

    sink.enable();
    await sink.flush();
    final file = File(join(root.path, 'logs', 'FlClashX_2026-10-20.log'));
    expect(file.readAsLinesSync(), ['[12:00:00] [INFO] early']);
  });

  test('writes keep their order across a dispose', () async {
    final sink = logger();
    sink.write(log('one'));
    await sink.dispose();
    sink.write(log('two'));
    await sink.flush();

    final file = File(join(root.path, 'logs', 'FlClashX_2026-10-20.log'));
    expect(file.readAsLinesSync(), [
      '[12:00:00] [INFO] one',
      '[12:00:00] [INFO] two',
    ]);
  });
}
