import 'dart:io';

import 'proxy_platform_interface.dart';
import 'src/linux_proxy.dart';
import 'src/macos_proxy.dart';
import 'src/proxy_command.dart';
import 'src/windows_proxy.dart';

export 'src/proxy_command.dart' show ProxyExecutableChecker, ProxyProcessRunner;

typedef ProxyPortProbe = Future<bool> Function(int port);

class Proxy {
  static const int _minPort = 1;
  static const int _maxPort = 65535;

  late final LinuxProxy _linuxProxy;
  late final MacosProxy _macosProxy;
  final ProxyPortProbe _isListening;

  Proxy({
    ProxyProcessRunner? processRunner,
    ProxyExecutableChecker? executableChecker,
    ProxyPortProbe? isListening,
  }) : _isListening = isListening ?? _acceptsConnections {
    final commandRunner = ProxyCommandRunner(processRunner ?? Process.run);
    _linuxProxy = LinuxProxy(
      commandRunner: commandRunner,
      executableChecker: executableChecker,
    );
    _macosProxy = MacosProxy(commandRunner: commandRunner);
  }

  Future<bool> startProxy(
    int port, [
    List<String> bypassDomain = const [],
  ]) async {
    if (port < _minPort || port > _maxPort) {
      return false;
    }
    return switch (Platform.operatingSystem) {
      'macos' => await _macosProxy.start(port, bypassDomain),
      'linux' => await _linuxProxy.start(
        port,
        bypassDomain,
        desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
        homeDir: Platform.environment['HOME'],
      ),
      'windows' => await ProxyPlatform.instance.startProxy(
        port,
        windowsBypassList(bypassDomain),
      ),
      String() => false,
    };
  }

  /// Turns off a proxy left on 127.0.0.1 at a port nothing listens on, which
  /// is broken whoever set it, and leaves any other setting alone.
  Future<bool> clearStaleProxy() async {
    return switch (Platform.operatingSystem) {
      'macos' => await _macosProxy.clearStale(_isListening),
      'linux' => await _linuxProxy.clearStale(
        _isListening,
        desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
        homeDir: Platform.environment['HOME'],
      ),
      'windows' => await ProxyPlatform.instance.clearStaleProxy(),
      String() => false,
    };
  }

  /// Only a refused connection shows the port is dead; a probe that fails
  /// any other way may be blocked while browsers still get through.
  static Future<bool> _acceptsConnections(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      return true;
    } on SocketException catch (error) {
      return error.osError?.errorCode != _connectionRefused;
    }
  }

  static int get _connectionRefused => Platform.isMacOS ? 61 : 111;

  Future<bool> stopProxy() async {
    return switch (Platform.operatingSystem) {
      'macos' => await _macosProxy.stop(),
      'linux' => await _linuxProxy.stop(
        desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
        homeDir: Platform.environment['HOME'],
      ),
      'windows' => await ProxyPlatform.instance.stopProxy(),
      String() => false,
    };
  }
}
