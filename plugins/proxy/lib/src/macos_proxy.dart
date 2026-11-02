import 'dart:io';

import 'proxy_command.dart';

class MacosProxy {
  final ProxyCommandRunner _commandRunner;

  MacosProxy({required ProxyCommandRunner commandRunner})
    : _commandRunner = commandRunner;

  Future<bool> start(int port, List<String> bypassDomain) async {
    final services = await _networkServices();
    return _commandRunner.run(
      services.expand(
        (service) => MacosProxyCommands.buildStart(service, port, bypassDomain),
      ),
    );
  }

  Future<bool> stop() async {
    final services = await _networkServices();
    return _commandRunner.run(services.expand(MacosProxyCommands.buildStop));
  }

  Future<bool> clearStale(Future<bool> Function(int port) isListening) async {
    final stale = <String>[];
    for (final service in await _networkServices()) {
      final enabled = await _enabledProxies(service);
      if (enabled != null && await isStaleLocalProxy(enabled, isListening)) {
        stale.add(service);
      }
    }
    if (stale.isEmpty) {
      return true;
    }
    return _commandRunner.run(stale.expand(MacosProxyCommands.buildStop));
  }

  /// Null when a setting could not be read.
  Future<List<ProxyEndpoint>?> _enabledProxies(String service) async {
    final enabled = <ProxyEndpoint>[];
    for (final query in const [
      '-getwebproxy',
      '-getsecurewebproxy',
      '-getsocksfirewallproxy',
    ]) {
      try {
        final result = await _commandRunner.process('/usr/sbin/networksetup', [
          query,
          service,
        ]);
        if (result.exitCode != 0) {
          return null;
        }
        final proxy = MacosProxyCommands.parseEnabledProxy(
          result.stdout.toString(),
        );
        if (proxy != null) {
          enabled.add(proxy);
        }
      } on ProcessException {
        return null;
      }
    }
    return enabled;
  }

  Future<List<String>> _networkServices() async {
    try {
      final result = await _commandRunner.process('/usr/sbin/networksetup', [
        '-listallnetworkservices',
      ]);
      if (result.exitCode != 0) {
        return [];
      }
      return MacosProxyCommands.parseNetworkServices(result.stdout.toString());
    } on ProcessException {
      return [];
    }
  }
}

class MacosProxyCommands {
  static List<ProxyCommand> buildStart(
    String service,
    int port,
    List<String> bypassDomain,
  ) {
    return [
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxy',
        service,
        proxyHost,
        '$port',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxy',
        service,
        proxyHost,
        '$port',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxy',
        service,
        proxyHost,
        '$port',
      ]),
      buildProxyBypass(service, bypassDomain),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxystate',
        service,
        'on',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxystate',
        service,
        'on',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'on',
      ]),
    ];
  }

  static List<ProxyCommand> buildStop(String service) {
    return [
      ProxyCommand('/usr/sbin/networksetup', [
        '-setautoproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'off',
      ]),
      buildProxyBypass(service, const []),
    ];
  }

  static ProxyCommand buildProxyBypass(
    String service,
    List<String> bypassDomain,
  ) {
    return ProxyCommand('/usr/sbin/networksetup', [
      '-setproxybypassdomains',
      service,
      if (bypassDomain.isEmpty) 'Empty' else ...bypassDomain,
    ]);
  }

  /// The proxy a `-get…proxy` query reports, or null when it is off.
  static ProxyEndpoint? parseEnabledProxy(String stdout) {
    final fields = <String, String>{};
    for (final line in stdout.split('\n')) {
      final separator = line.indexOf(':');
      if (separator > 0) {
        fields[line.substring(0, separator).trim()] = line
            .substring(separator + 1)
            .trim();
      }
    }
    if (fields['Enabled'] != 'Yes') {
      return null;
    }
    return (
      host: fields['Server'] ?? '',
      port: int.tryParse(fields['Port'] ?? '') ?? 0,
    );
  }

  static List<String> parseNetworkServices(String stdout) {
    return stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('*'))
        .where((line) => !line.startsWith('An asterisk '))
        .toList();
  }
}
