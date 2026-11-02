import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart' show ProxyState;
import 'package:proxy/proxy.dart';

final proxy = system.isDesktop && !safeModeBuild ? Proxy() : null;

final systemProxyQueue = proxy == null
    ? null
    : SystemProxyQueue(proxy!, const PreferencesSystemProxyOwnership());

abstract interface class SystemProxyOwnership {
  Future<bool> read();

  Future<bool> save(bool applied);
}

final class PreferencesSystemProxyOwnership implements SystemProxyOwnership {
  const PreferencesSystemProxyOwnership();

  @override
  Future<bool> read() => preferences.getSystemProxyApplied();

  @override
  Future<bool> save(bool applied) =>
      preferences.saveSystemProxyApplied(applied);
}

/// Exit's stop goes through the same queue as every other change, so a start
/// still waiting behind a slow call cannot turn the proxy back on after it.
/// Only undoes a start of this run, so a stop leaves others' settings alone.
/// A start is also kept on disk: a launch after a run that crashed or was
/// killed with the proxy on clears it, but only if it still points at a
/// port nothing listens on, since someone may have set another one since.
class SystemProxyQueue {
  final Proxy _proxy;
  final SystemProxyOwnership _ownership;
  Future<void> _tail = Future.value();
  bool _closed = false;
  bool _applied = false;
  bool? _leftByLastRun;

  SystemProxyQueue(this._proxy, this._ownership);

  Future<void> apply(ProxyState state) {
    return _enqueue(() async {
      if (_closed) {
        return;
      }
      if (state.isStart && state.systemProxy) {
        _applied = true;
        _leftByLastRun = false;
        await _record(true);
        if (!await _proxy.startProxy(state.port, state.bassDomain)) {
          _logFailure();
        }
      } else {
        await _stop();
      }
    });
  }

  Future<void> close() {
    _closed = true;
    return _enqueue(_stop);
  }

  Future<void> _stop() async {
    if (_applied) {
      if (!await _proxy.stopProxy()) {
        _logFailure();
        return;
      }
      _applied = false;
      await _record(false);
      return;
    }
    if (_leftByLastRun ??= await _ownership.read()) {
      if (!await _proxy.clearStaleProxy()) {
        _logFailure();
        return;
      }
      _leftByLastRun = false;
      await _record(false);
    }
  }

  /// Saved on every start, so one that failed is tried again by the next.
  Future<void> _record(bool applied) async {
    try {
      if (await _ownership.save(applied)) {
        return;
      }
    } catch (_) {}
    commonPrint.log(
      'Failed to record the system proxy as ${applied ? 'set' : 'cleared'}',
      logLevel: LogLevel.warning,
    );
  }

  void _logFailure() {
    commonPrint.log('update system proxy failed', logLevel: LogLevel.warning);
  }

  Future<void> _enqueue(Future<void> Function() task) {
    return _tail = _tail.then((_) => task()).catchError((Object error) {
      commonPrint.log(
        'update system proxy failed: $error',
        logLevel: LogLevel.warning,
      );
    });
  }
}

String proxyEnvCommand(int port, {required bool isWindows}) {
  final url = 'http://127.0.0.1:$port';
  return isWindows ? 'set \$env:all_proxy=$url' : 'export all_proxy=$url';
}
