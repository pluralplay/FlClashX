import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chain.dart';

/// Kept beside the app's settings rather than in the database, so the beta
/// can be dropped without a schema migration; backups do not carry it yet.
String _keyOf(int profileId) => 'proxy_chains_$profileId';

final proxyChainsProvider =
    AsyncNotifierProvider.family<ProxyChainsNotifier, List<ProxyChain>, int>(
      ProxyChainsNotifier.new,
    );

class ProxyChainsSaveException implements Exception {
  const ProxyChainsSaveException();
}

class ProxyChainsNotifier extends AsyncNotifier<List<ProxyChain>> {
  ProxyChainsNotifier(this.profileId);

  final int profileId;

  @override
  Future<List<ProxyChain>> build() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.get(_keyOf(profileId));
    if (raw is! String) {
      return const [];
    }
    try {
      final json = jsonDecode(raw);
      return [
        if (json is List)
          for (final item in json)
            if (ProxyChain.fromJson(item) case final ProxyChain chain) chain,
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _queue = Future.value();

  Future<void> put(ProxyChain chain) => _change((chains) {
    final index = chains.indexWhere((item) => item.id == chain.id);
    return index == -1
        ? [...chains, chain]
        : [...chains.take(index), chain, ...chains.skip(index + 1)];
  });

  Future<void> remove(String id) => _change(
    (chains) => [
      for (final chain in chains)
        if (chain.id != id) chain,
    ],
  );

  /// One change at a time, each from the list the last one left.
  Future<void> _change(
    List<ProxyChain> Function(List<ProxyChain> chains) change,
  ) {
    final run = _queue.then((_) async => _save(change(await future)));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  @visibleForTesting
  static Future<bool> Function(String key, String value) write =
      (key, value) async =>
          (await SharedPreferences.getInstance()).setString(key, value);

  Future<void> _save(List<ProxyChain> chains) async {
    final bool saved;
    try {
      saved = await write(
        _keyOf(profileId),
        jsonEncode([for (final chain in chains) chain.toJson()]),
      );
    } catch (_) {
      throw const ProxyChainsSaveException();
    }
    if (!saved) {
      throw const ProxyChainsSaveException();
    }
    state = AsyncData(chains);
  }
}

/// The enabled chains of [profileId] as the config build takes them, and a
/// dependency of whoever awaits it.
Future<List<Map<String, Object?>>> watchEnabledProxyChains(
  Ref ref,
  int profileId,
) async {
  final chains = await ref.watch(proxyChainsProvider(profileId).future);
  return [
    for (final chain in chains)
      if (chain.enabled) chain.toJson(),
  ];
}

/// Never fails the profile's deletion; a leftover is only dead weight.
Future<void> forgetProxyChains(Ref ref, int profileId) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_keyOf(profileId));
  } catch (_) {
  } finally {
    ref.invalidate(proxyChainsProvider(profileId));
  }
}
