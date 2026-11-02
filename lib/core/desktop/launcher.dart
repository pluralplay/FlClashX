import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';

import 'model.dart';

typedef CoreProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

abstract interface class CoreProcessLauncher {
  Future<CoreProcessLease> start({
    required String sessionId,
    required String address,
  });
}

abstract interface class DesktopCoreLauncherResolver {
  Future<CoreProcessLauncher> resolve();
}

final class DirectCoreLauncher implements CoreProcessLauncher {
  final CoreProcessStarter _startProcess;
  final String corePath;

  DirectCoreLauncher({CoreProcessStarter? startProcess, String? corePath})
    : _startProcess = startProcess ?? Process.start,
      corePath = corePath ?? appPath.corePath;

  @override
  Future<CoreProcessLease> start({
    required String sessionId,
    required String address,
  }) async {
    final process = await _startProcess(corePath, [address]);
    final lease = DirectCoreLease(sessionId: sessionId, process: process);
    process.stdout.listen((_) {});
    process.stderr.listen((data) {
      final error = utf8.decode(data);
      if (error.isNotEmpty) {
        lease._noteOutput(error);
        commonPrint.log(error, logLevel: LogLevel.warning);
      }
    });
    return lease;
  }
}

final class DirectCoreLease implements CoreProcessLease {
  @override
  final String sessionId;

  final Process _process;
  Future<CoreProcessStopResult>? _stopOperation;
  String? _crashHeadline;
  String _partialLine = '';

  static const _longestLine = 4096;
  static final _goCrashHeadline = RegExp(r'^(?:panic|fatal error|SIG[A-Z]+): ');

  DirectCoreLease({required this.sessionId, required Process process})
    : _process = process;

  @override
  CoreProcessOwner get owner => CoreProcessOwner.direct;

  @override
  int get pid => _process.pid;

  @override
  String? get crashHeadline => _crashHeadline;

  void _noteOutput(String output) {
    final lines = '$_partialLine$output'.split('\n');
    final partial = lines.removeLast();
    _partialLine = partial.length > _longestLine
        ? partial.substring(0, _longestLine)
        : partial;
    for (final line in lines) {
      if (_goCrashHeadline.hasMatch(line)) {
        _crashHeadline = line.trim();
      }
    }
  }

  @override
  Future<CoreProcessStopResult> stop(Duration timeout) {
    final stopOperation = _stopOperation;
    if (stopOperation != null) {
      return stopOperation;
    }
    final nextOperation = _stop(timeout).then((result) {
      if (!result.exitConfirmed) {
        _stopOperation = null;
      }
      return result;
    });
    _stopOperation = nextOperation;
    return nextOperation;
  }

  Future<CoreProcessStopResult> _stop(Duration timeout) async {
    final stopped = _process.kill();
    try {
      await _process.exitCode.timeout(timeout);
      return CoreProcessStopResult(stopped: stopped, exitConfirmed: true);
    } on TimeoutException {
      return CoreProcessStopResult(stopped: stopped, exitConfirmed: false);
    }
  }
}
