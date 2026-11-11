import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
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

  test('the archive holds every file of today, the last line too', () async {
    final logs = Directory(join(root.path, 'logs'))
      ..createSync(recursive: true);
    for (final name in [
      'FlClashX_2026-10-19.log',
      'FlClashX_2026-10-20_1.log',
      'notes.txt',
    ]) {
      File(join(logs.path, name)).writeAsStringSync(name);
    }
    final sink = logger();
    sink.write(log('just now'));

    final path = await sink.archiveToday(root.path);

    expect(basename(path!), 'FlClashX_logs_2026-10-20_15-00-00.zip');
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    expect(
      {
        for (final file in archive.files)
          file.name: String.fromCharCodes(file.content),
      },
      {
        'FlClashX_2026-10-20.log': '[12:00:00] [INFO] just now\n',
        'FlClashX_2026-10-20_1.log': 'FlClashX_2026-10-20_1.log',
      },
    );
  });

  test('a share keeps the archives an earlier one handed out', () async {
    File(join(root.path, 'logs', 'FlClashX_2026-10-20.log'))
      ..createSync(recursive: true)
      ..writeAsStringSync('line');
    final shares = Directory(join(root.path, 'share'))..createSync();
    final stale =
        File(join(shares.path, 'FlClashX_logs_2026-10-18_09-00-00.zip'))
          ..writeAsStringSync('old')
          ..setLastModifiedSync(DateTime(2026, 10, 19, 14));
    final unrelated = File(join(shares.path, 'notes.zip'))
      ..writeAsStringSync('x')
      ..setLastModifiedSync(DateTime(2026, 10, 1));
    final sink = logger();

    final first = await sink.archiveToday(shares.path);
    File(first!).setLastModifiedSync(DateTime(2026, 10, 20, 15));
    final second = await sink.archiveToday(shares.path);

    expect(basename(second!), 'FlClashX_logs_2026-10-20_15-00-00_2.zip');
    expect(File(first).existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('a second export waits until the first has its archive', () async {
    File(join(root.path, 'logs', 'FlClashX_2026-10-20.log'))
      ..createSync(recursive: true)
      ..writeAsStringSync('line');
    final shares = Directory(join(root.path, 'share'))..createSync();
    final written = <String>[];
    final firstEntered = Completer<void>();
    final firstHeld = Completer<void>();
    final sink = FileLogger(
      directory: () async => join(root.path, 'logs'),
      now: () => DateTime(2026, 10, 20, 15),
      writeArchive: (request) async {
        written.add(basename(request.archivePath));
        if (written.length == 1) {
          firstEntered.complete();
          await firstHeld.future;
        }
        File(request.archivePath).writeAsStringSync('zip');
      },
    )..enable();

    final first = sink.archiveToday(shares.path);
    final second = sink.archiveToday(shares.path);
    await firstEntered.future;
    // Real time for an unserialized second export to reach its writer.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(written, ['FlClashX_logs_2026-10-20_15-00-00.zip']);

    firstHeld.complete();
    await Future.wait([first, second]);
    expect(written, [
      'FlClashX_logs_2026-10-20_15-00-00.zip',
      'FlClashX_logs_2026-10-20_15-00-00_2.zip',
    ]);
  });

  test('a day without logs has no archive', () async {
    final logs = Directory(join(root.path, 'logs'))
      ..createSync(recursive: true);
    File(join(logs.path, 'FlClashX_2026-10-19.log')).writeAsStringSync('x');

    expect(await logger().archiveToday(root.path), isNull);
    expect(Directory(root.path).listSync().whereType<File>(), isEmpty);
  });
}
