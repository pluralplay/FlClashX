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

  Future<void> save(bool applied);
}

final class PreferencesSystemProxyOwnership implements SystemProxyOwnership {
  const PreferencesSystemProxyOwnership();

  @override
  Future<bool> read() => preferences.getSystemProxyApplied();

  @override
  Future<void> save(bool applied) =>
      preferences.saveSystemProxyApplied(applied);
}

/// Exit's stop goes through the same queue as every other change, so a start
/// still waiting behind a slow call cannot turn the proxy back on after it.
/// Only undoes a start of this app, so a stop leaves others' settings alone;
/// that start is kept on disk, so a run that crashed or was killed with the
/// proxy on is undone by the next launch.
class SystemProxyQueue {
  final Proxy _proxy;
  final SystemProxyOwnership _ownership;
  Future<void> _tail = Future.value();
  bool _closed = false;
  bool? _applied;

  SystemProxyQueue(this._proxy, this._ownership);

  Future<void> apply(ProxyState state) {
    return _enqueue(() async {
      if (_closed) {
        return;
      }
      if (state.isStart && state.systemProxy) {
        await _setApplied(true);
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
    if (!(_applied ??= await _ownership.read())) {
      return;
    }
    if (!await _proxy.stopProxy()) {
      _logFailure();
      return;
    }
    await _setApplied(false);
  }

  Future<void> _setApplied(bool applied) async {
    if (_applied == applied) {
      return;
    }
    _applied = applied;
    await _ownership.save(applied);
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
