import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/core_cli.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory home;
  late String endpointPath;
  late CoreCliServer server;
  final said = <String>[];

  setUp(() {
    home = Directory.systemTemp.createTempSync('core_cli_test');
    endpointPath = '${home.path}/core-cli.json';
    server = CoreCliServer(endpointPath: () async => endpointPath);
    said.clear();
  });

  tearDown(() async {
    await server.stop();
    home.deleteSync(recursive: true);
  });

  Future<CoreCliExit> ask() =>
      runRestartCoreCli(endpointPath: () async => endpointPath, say: said.add);

  test('restarts the Core of the running app and says so', () async {
    var restarts = 0;
    await server.start(restartCore: () async => ++restarts > 0);

    expect(await ask(), CoreCliExit.restarted);
    expect(restarts, 1);
    expect(said, ['Core restarted']);
    if (!Platform.isWindows) {
      expect(File(endpointPath).statSync().modeString(), 'rw-------');
    }
  });

  test('a restart that fails or throws exits with failed', () async {
    await server.start(restartCore: () async => false);
    expect(await ask(), CoreCliExit.failed);
    await server.stop();

    await server.start(restartCore: () async => throw StateError('closed'));
    expect(await ask(), CoreCliExit.failed);
    expect(said.last, contains('closed'));
  });

  test('no running app, or a stale port, exits with not running', () async {
    expect(await ask(), CoreCliExit.notRunning);

    await server.start(restartCore: () async => true);
    await server.stop();
    expect(File(endpointPath).existsSync(), isTrue);
    expect(await ask(), CoreCliExit.notRunning);
  });

  test('a request without the token restarts nothing', () async {
    var restarts = 0;
    await server.start(restartCore: () async => ++restarts > 0);
    final endpoint = CoreCliEndpoint.fromJson(
      jsonDecode(File(endpointPath).readAsStringSync()),
    )!;
    File(endpointPath).writeAsStringSync(
      jsonEncode(CoreCliEndpoint(port: endpoint.port, token: 'x').toJson()),
    );

    expect(await ask(), CoreCliExit.failed);
    expect(restarts, 0);
    expect(said.single, contains('unauthorized'));
  });
}
