import 'dart:convert';

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

class ProxyChainsNotifier extends AsyncNotifier<List<ProxyChain>> {
  ProxyChainsNotifier(this.profileId);

  final int profileId;

  @override
  Future<List<ProxyChain>> build() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_keyOf(profileId));
    if (raw == null) {
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

  Future<void> put(ProxyChain chain) async {
    final chains = [...await future];
    final index = chains.indexWhere((item) => item.id == chain.id);
    if (index == -1) {
      chains.add(chain);
    } else {
      chains[index] = chain;
    }
    await _save(chains);
  }

  Future<void> remove(String id) async {
    final chains = await future;
    await _save([
      for (final chain in chains)
        if (chain.id != id) chain,
    ]);
  }

  Future<void> _save(List<ProxyChain> chains) async {
    state = AsyncData(chains);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _keyOf(profileId),
      jsonEncode([for (final chain in chains) chain.toJson()]),
    );
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
