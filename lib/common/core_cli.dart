import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'path.dart';
import 'print.dart';

/// `FlClashX --restart-core` asks the running app on this data directory to
/// restart its Core, as the dashboard's button does, and exits with one of
/// these codes.
const restartCoreArgument = '--restart-core';

enum CoreCliExit {
  restarted(0),
  failed(1),
  notRunning(2),
  noAnswer(3);

  const CoreCliExit(this.code);

  final int code;
}

const _restartCommand = 'restart-core';
const _connectTimeout = Duration(seconds: 3);
// A restart through the Helper can wait out a Core that is slow to stop.
const _answerTimeout = Duration(seconds: 90);

/// The running app listens on a loopback port it writes, with a token, to a
/// file in its own data directory that only its user can read: macOS leaves
/// that directory open to other users, so the file itself is 0600.
class CoreCliEndpoint {
  const CoreCliEndpoint({required this.port, required this.token});

  final int port;
  final String token;

  Map<String, Object?> toJson() => {'port': port, 'token': token};

  static CoreCliEndpoint? fromJson(Object? json) => switch (json) {
    {'port': final int port, 'token': final String token} => CoreCliEndpoint(
      port: port,
      token: token,
    ),
    _ => null,
  };
}

Future<CoreCliExit> runRestartCoreCli({
  Future<String> Function()? endpointPath,
  void Function(String line)? say,
}) async {
  final out = say ?? stdout.writeln;
  CoreCliEndpoint? endpoint;
  try {
    final file = File(await (endpointPath ?? () => appPath.coreCliPath)());
    endpoint = CoreCliEndpoint.fromJson(jsonDecode(await file.readAsString()));
  } catch (_) {
    endpoint = null;
  }
  if (endpoint == null) {
    out('FlClashX is not running');
    return CoreCliExit.notRunning;
  }
  final Socket socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      endpoint.port,
      timeout: _connectTimeout,
    );
  } on SocketException {
    out('FlClashX is not running');
    return CoreCliExit.notRunning;
  }
  try {
    socket.writeln(
      jsonEncode({'token': endpoint.token, 'command': _restartCommand}),
    );
    await socket.flush();
    final line = await utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .first
        .timeout(_answerTimeout);
    final answer = jsonDecode(line);
    if (answer case {'ok': true}) {
      out('Core restarted');
      return CoreCliExit.restarted;
    }
    final error = answer is Map ? answer['error'] : null;
    out('Core restart failed${error is String ? ': $error' : ''}');
    return CoreCliExit.failed;
  } catch (error) {
    out('FlClashX did not answer: $error');
    return CoreCliExit.noAnswer;
  } finally {
    socket.destroy();
  }
}

class CoreCliServer {
  CoreCliServer({Future<String> Function()? endpointPath})
    : _endpointPath = endpointPath ?? (() => appPath.coreCliPath);

  final Future<String> Function() _endpointPath;
  ServerSocket? _server;

  @visibleForTesting
  int? get port => _server?.port;

  Future<void> start({required Future<bool> Function() restartCore}) async {
    if (_server != null) {
      return;
    }
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      final token = _newToken();
      final endpoint = CoreCliEndpoint(port: server.port, token: token);
      final file = File(await _endpointPath());
      final staging = File('${file.path}.tmp');
      await staging.writeAsString('', flush: true);
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', ['600', staging.path]);
        if (chmod.exitCode != 0) {
          throw FileSystemException('chmod failed', staging.path);
        }
      }
      await staging.writeAsString(jsonEncode(endpoint.toJson()), flush: true);
      await staging.rename(file.path);
      server.listen(
        (socket) => unawaited(_answer(socket, token, restartCore)),
        onError: (Object error) => commonPrint.log('core cli: $error'),
      );
    } catch (error) {
      commonPrint.log('core cli unavailable: $error');
      await stop();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
  }

  Future<void> _answer(
    Socket socket,
    String token,
    Future<bool> Function() restartCore,
  ) async {
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(_connectTimeout);
      final request = jsonDecode(line);
      final Map<String, Object?> answer;
      if (request case {
        'token': final String sent,
        'command': final command,
      } when sent == token) {
        answer = command == _restartCommand
            ? await _restart(restartCore)
            : {'ok': false, 'error': 'unknown command $command'};
      } else {
        answer = {'ok': false, 'error': 'unauthorized'};
      }
      socket.writeln(jsonEncode(answer));
      await socket.flush();
    } catch (error) {
      commonPrint.log('core cli request failed: $error');
    } finally {
      socket.destroy();
    }
  }

  Future<Map<String, Object?>> _restart(
    Future<bool> Function() restartCore,
  ) async {
    try {
      final restarted = await restartCore();
      return restarted ? {'ok': true} : {'ok': false};
    } catch (error) {
      return {'ok': false, 'error': '$error'};
    }
  }

  static String _newToken() {
    final random = Random.secure();
    return base64Url.encode(List.generate(24, (_) => random.nextInt(256)));
  }
}

final coreCliServer = CoreCliServer();
