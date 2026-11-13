import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chain.dart';

/// Kept beside the app's settings rather than in the database, so the beta
/// can be dropped without a schema migration.
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
///
/// Watches at the call, so an async provider must call it before its first
/// await: a ref watched after one may already be disposed.
Future<List<Map<String, Object?>>> watchEnabledProxyChains(
  Ref ref,
  int profileId,
) => ref
    .watch(proxyChainsProvider(profileId).future)
    .then(
      (chains) => [
        for (final chain in chains)
          if (chain.enabled) chain.toJson(),
      ],
    );

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

const proxyChainsBackupKey = 'proxyChains';

Future<Map<String, String>> proxyChainsBackup(Iterable<int> profileIds) async {
  final preferences = await SharedPreferences.getInstance();
  return {
    for (final profileId in profileIds)
      if (preferences.get(_keyOf(profileId)) case final String raw)
        '$profileId': raw,
  };
}

/// An older backup, which carried no chains, leaves them as they are.
Future<void> restoreProxyChains(
  Ref ref,
  Object? backup,
  Iterable<int> profileIds,
) async {
  if (backup is! Map) {
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  var saved = true;
  for (final profileId in profileIds) {
    final raw = backup['$profileId'];
    try {
      saved &= raw is String && _isChainList(raw)
          ? await ProxyChainsNotifier.write(_keyOf(profileId), raw)
          : await preferences.remove(_keyOf(profileId));
    } catch (_) {
      saved = false;
    }
    ref.invalidate(proxyChainsProvider(profileId));
  }
  if (!saved) {
    throw const ProxyChainsSaveException();
  }
}

bool _isChainList(String raw) {
  try {
    return jsonDecode(raw) is List;
  } on FormatException {
    return false;
  }
}
