import 'dart:io';

import 'package:flutter/foundation.dart';

const proxyHost = '127.0.0.1';

typedef ProxyProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

typedef ProxyExecutableChecker = Future<bool> Function(String executable);

typedef ProxyEndpoint = ({String host, int port});

/// Whether [enabled], every proxy a setting turns on, points at [proxyHost]
/// on ports nothing listens on: one other proxy in it, or one whose port is
/// left to a default, may be someone's working setup, which turning the
/// setting off would take down.
Future<bool> isStaleLocalProxy(
  List<ProxyEndpoint> enabled,
  Future<bool> Function(int port) isListening,
) async {
  if (enabled.isEmpty ||
      enabled.any((proxy) => proxy.host != proxyHost || proxy.port <= 0)) {
    return false;
  }
  for (final port in {for (final proxy in enabled) proxy.port}) {
    if (await isListening(port)) {
      return false;
    }
  }
  return true;
}

@immutable
class ProxyCommand {
  final String executable;
  final List<String> args;
  final bool runInShell;
  final bool optional;

  ProxyCommand(
    this.executable,
    List<String> args, {
    this.runInShell = false,
    this.optional = false,
  }) : args = List.unmodifiable(args);
}

class ProxyCommandRunner {
  final ProxyProcessRunner _processRunner;

  ProxyCommandRunner(this._processRunner);

  Future<ProcessResult> process(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) {
    return _processRunner(executable, arguments, runInShell: runInShell);
  }

  Future<bool> run(Iterable<ProxyCommand> commands) async {
    var executed = false;
    for (final command in commands) {
      executed = true;
      if (!await _succeeds(command) && !command.optional) {
        return false;
      }
    }
    return executed;
  }

  Future<bool> _succeeds(ProxyCommand command) async {
    try {
      final result = await process(
        command.executable,
        command.args,
        runInShell: command.runInShell,
      );
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
