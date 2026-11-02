import 'dart:async';

import 'package:fl_clash/common/proxy.dart';
import 'package:fl_clash/models/models.dart' show ProxyState;
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';

class _FakeProxy implements Proxy {
  final List<String> calls = [];
  Future<bool>? held;
  Error? failure;

  Future<bool> _call(String name) async {
    calls.add(name);
    final error = failure;
    failure = null;
    if (error != null) {
      throw error;
    }
    final result = held ?? Future.value(true);
    held = null;
    return result;
  }

  @override
  Future<bool> startProxy(int port, [List<String> bypassDomain = const []]) {
    return _call('start $port');
  }

  @override
  Future<bool> stopProxy() => _call('stop');
}

class _MemoryOwnership implements SystemProxyOwnership {
  bool applied;
  final List<bool> saves = [];

  _MemoryOwnership([this.applied = false]);

  @override
  Future<bool> read() async => applied;

  @override
  Future<void> save(bool applied) async {
    saves.add(applied);
    this.applied = applied;
  }
}

ProxyState _state({required bool isStart}) {
  return ProxyState(
    isStart: isStart,
    systemProxy: true,
    bassDomain: const [],
    port: 7890,
  );
}

void main() {
  test('applies changes in the order they come', () async {
    final proxy = _FakeProxy();
    final queue = SystemProxyQueue(proxy, _MemoryOwnership());

    unawaited(queue.apply(_state(isStart: true)));
    await queue.apply(_state(isStart: false));

    expect(proxy.calls, ['start 7890', 'stop']);
  });

  test('close stops last and drops the starts queued before it', () async {
    final proxy = _FakeProxy();
    final queue = SystemProxyQueue(proxy, _MemoryOwnership());
    final inFlight = Completer<bool>();
    proxy.held = inFlight.future;

    unawaited(queue.apply(_state(isStart: true)));
    await pumpEventQueue();
    unawaited(queue.apply(_state(isStart: true)));
    final closed = queue.close();
    await pumpEventQueue();
    expect(proxy.calls, ['start 7890']);

    inFlight.complete(true);
    await closed;
    await queue.apply(_state(isStart: true));

    expect(proxy.calls, ['start 7890', 'stop']);
  });

  test('a failing call does not stall the queue', () async {
    final proxy = _FakeProxy();
    final queue = SystemProxyQueue(proxy, _MemoryOwnership());
    proxy.failure = StateError('channel gone');

    await queue.apply(_state(isStart: true));
    await queue.apply(_state(isStart: false));

    expect(proxy.calls, ['start 7890', 'stop']);
  });

  test('leaves a proxy it never set alone', () async {
    final proxy = _FakeProxy();
    final queue = SystemProxyQueue(proxy, _MemoryOwnership());

    await queue.apply(_state(isStart: false));
    await queue.close();

    expect(proxy.calls, isEmpty);
  });

  test(
    'a launch after a run that died with the proxy on turns it off',
    () async {
      final proxy = _FakeProxy();
      final ownership = _MemoryOwnership(true);
      final queue = SystemProxyQueue(proxy, ownership);

      await queue.apply(_state(isStart: false));
      await queue.close();

      expect(proxy.calls, ['stop']);
      expect(ownership.applied, isFalse);
    },
  );

  test('keeps a start on disk until a stop succeeds', () async {
    final proxy = _FakeProxy();
    final ownership = _MemoryOwnership();
    final queue = SystemProxyQueue(proxy, ownership);
    final started = Completer<bool>();
    proxy.held = started.future;

    unawaited(queue.apply(_state(isStart: true)));
    await pumpEventQueue();
    expect(proxy.calls, ['start 7890']);
    expect(ownership.applied, isTrue);

    started.complete(true);
    proxy.held = Future.value(false);
    await queue.apply(_state(isStart: false));
    expect(ownership.applied, isTrue);

    await queue.apply(_state(isStart: false));
    expect(ownership.applied, isFalse);
    expect(ownership.saves, [true, false]);
  });

  test('tries a failed stop again on close', () async {
    final proxy = _FakeProxy();
    final queue = SystemProxyQueue(proxy, _MemoryOwnership());

    await queue.apply(_state(isStart: true));
    proxy.held = Future.value(false);
    await queue.apply(_state(isStart: false));
    await queue.close();
    await queue.close();

    expect(proxy.calls, ['start 7890', 'stop', 'stop']);
  });
}
