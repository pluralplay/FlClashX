import 'dart:convert';

import 'chain.dart';

enum ProxyChainIssueKind {
  missingHop,
  providerHop,
  unchainableHop,
  repeatedHop,
  nameTaken,
}

typedef ProxyChainIssue = ({ProxyChainIssueKind kind, String name});

const _builtins = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'COMPATIBLE',
  'PASS',
  'PASS-RULE',
  'GLOBAL',
};

/// Types whose mihomo constructors ignore `dialer-proxy`.
const _unchainableTypes = {'direct', 'dns', 'reject', 'rematch'};

const _groupTypes = {'select', 'url-test', 'fallback', 'load-balance'};

const _membershipKeys = {
  'name',
  'type',
  'proxies',
  'use',
  'include-all',
  'include-all-proxies',
  'include-all-providers',
  'filter',
  'exclude-filter',
  'exclude-type',
  'hidden',
  'default-selected',
};

/// Where mihomo's `AdapterType`, which `exclude-type` matches, differs from
/// the config's own type name.
const _adapterTypes = {
  'ss': 'Shadowsocks',
  'ssr': 'ShadowsocksR',
  'select': 'Selector',
  'load-balance': 'LoadBalance',
};

class _Group {
  _Group(Map raw)
    : type = _string(raw['type']) ?? '',
      explicit = _strings(raw['proxies']),
      includesProxies =
          raw['include-all'] == true || raw['include-all-proxies'] == true,
      usesProviders =
          raw['include-all'] == true ||
          raw['include-all-providers'] == true ||
          _strings(raw['use']).isNotEmpty,
      filter = _string(raw['filter']),
      excludeFilter = _string(raw['exclude-filter']),
      excludeType = _string(raw['exclude-type']),
      hidden = raw['hidden'] == true;

  final String type;
  final List<String> explicit;
  final bool includesProxies;
  final bool usesProviders;
  final String? filter;
  final String? excludeFilter;
  final String? excludeType;
  final bool hidden;
}

/// One profile's outbounds, with group members resolved as mihomo does.
class ProxyChainGraph {
  ProxyChainGraph._(this._proxyTypes, this._groups, this._providers);

  factory ProxyChainGraph.fromRaw(Map rawConfig) {
    final providers = rawConfig['proxy-providers'];
    return ProxyChainGraph._(
      {
        for (final proxy in _maps(rawConfig['proxies']))
          if (proxy['name'] case final String name)
            name: _string(proxy['type'])?.toLowerCase() ?? '',
      },
      {
        for (final group in _maps(rawConfig['proxy-groups']))
          if (group['name'] case final String name) name: _Group(group),
      },
      {if (providers is Map) ...providers.keys.whereType<String>()},
    );
  }

  final Map<String, String> _proxyTypes;
  final Map<String, _Group> _groups;
  final Set<String> _providers;
  final _members = <String, List<String>?>{};
  final _leaves = <String, List<String>?>{};
  late final List<String> _allProxies = [..._proxyTypes.keys]
    ..sort(_compareBytes);

  Map<String, String> get groupTypes => {
    for (final MapEntry(:key, :value) in _groups.entries)
      if (!value.hidden) key: value.type,
  };

  Map<String, String> get proxyTypes => _proxyTypes;

  bool has(String name) =>
      _proxyTypes.containsKey(name) || _groups.containsKey(name);

  bool _reserved(String name) =>
      has(name) || _builtins.contains(name) || _providers.contains(name);

  /// Null when a filter is not a pattern Dart reads.
  List<String>? membersOf(String name) {
    if (_members.containsKey(name)) {
      return _members[name];
    }
    final group = _groups[name];
    return _members[name] = group == null ? null : _resolveMembers(group);
  }

  List<String>? _resolveMembers(_Group group) {
    final included = <String>[];
    if (group.includesProxies) {
      final filters = _patterns(group.filter);
      if (filters == null) {
        return null;
      }
      included.addAll(
        filters.isEmpty
            ? _allProxies
            : _allProxies.where((p) => filters.any((f) => f.hasMatch(p))),
      );
    }
    final excluded = _patterns(group.excludeFilter);
    if (excluded == null) {
      return null;
    }
    final excludedTypes = {
      for (final type in group.excludeType?.split('|') ?? const <String>[])
        type.trim().toLowerCase(),
    };
    return [
      for (final member in [...group.explicit, ...included])
        if (!excluded.any((f) => f.hasMatch(member)) &&
            !excludedTypes.contains(_adapterTypeOf(member)))
          member,
    ];
  }

  String _adapterTypeOf(String name) {
    final type = _proxyTypes[name] ?? _groups[name]?.type ?? name;
    return (_adapterTypes[type] ?? type).replaceAll('-', '').toLowerCase();
  }

  /// Null when [name] also reaches provider proxies, which cannot be cloned.
  List<String>? leavesOf(String name) => _leavesOf(name, <String>{});

  List<String>? _leavesOf(String name, Set<String> visiting) {
    if (_proxyTypes.containsKey(name)) {
      return [name];
    }
    if (_leaves.containsKey(name)) {
      return _leaves[name];
    }
    final group = _groups[name];
    if (group == null) {
      return const [];
    }
    if (group.usesProviders || !visiting.add(name)) {
      return null;
    }
    final leaves = _groupLeaves(membersOf(name), visiting);
    visiting.remove(name);
    return _leaves[name] = leaves;
  }

  List<String>? _groupLeaves(List<String>? members, Set<String> visiting) {
    if (members == null) {
      return null;
    }
    final found = <String>{};
    for (final member in members) {
      final leaves = _leavesOf(member, visiting);
      if (leaves == null) {
        return null;
      }
      found.addAll(leaves);
    }
    return found.toList();
  }

  /// Whether a hop past the entry can be built from [name].
  bool isChainable(String name) {
    final leaves = leavesOf(name);
    return leaves != null &&
        leaves.isNotEmpty &&
        !leaves.any((leaf) => _unchainableTypes.contains(_proxyTypes[leaf]));
  }

  ProxyChainIssue? _hopIssueOf(ProxyChain chain) {
    for (final hop in chain.hops) {
      if (!has(hop)) {
        return (kind: ProxyChainIssueKind.missingHop, name: hop);
      }
    }
    if (chain.hops.toSet().length != chain.hops.length) {
      return (kind: ProxyChainIssueKind.repeatedHop, name: chain.name);
    }
    for (final hop in chain.hops.skip(1)) {
      final leaves = leavesOf(hop);
      if (leaves == null) {
        return (kind: ProxyChainIssueKind.providerHop, name: hop);
      }
      if (!isChainable(hop)) {
        return (kind: ProxyChainIssueKind.unchainableHop, name: hop);
      }
    }
    return null;
  }

  /// By chain id; a name goes to the first enabled chain that can take it.
  Map<String, ProxyChainIssue> issuesOf(Iterable<ProxyChain> chains) {
    final names = <String>{};
    final issues = <String, ProxyChainIssue>{};
    for (final chain in chains) {
      final issue =
          _hopIssueOf(chain) ??
          (_reserved(chain.name) || names.contains(chain.name)
              ? (kind: ProxyChainIssueKind.nameTaken, name: chain.name)
              : null);
      if (issue != null) {
        issues[chain.id] = issue;
      } else if (chain.enabled) {
        names.add(chain.name);
      }
    }
    return issues;
  }
}

/// Adds a group named after each chain whose members are clones of the exit's
/// proxies that dial through the hops before it, mihomo's `dialer-proxy`. A
/// middle group hop becomes a hidden group of its own clones. Chains that
/// cannot be built are left out.
void applyProxyChains(Map rawConfig, Iterable<Object?> chainsJson) {
  final chains = [
    for (final json in chainsJson)
      if (ProxyChain.fromJson(json) case final ProxyChain chain
          when chain.enabled)
        chain,
  ];
  if (chains.isEmpty) {
    return;
  }
  final graph = ProxyChainGraph.fromRaw(rawConfig);
  final issues = graph.issuesOf(chains);
  final buildable = [
    for (final chain in chains)
      if (!issues.containsKey(chain.id)) chain,
  ];
  if (buildable.isEmpty) {
    return;
  }
  final groupList = _pinIncludeAll(graph, _maps(rawConfig['proxy-groups']));
  if (groupList == null) {
    return;
  }
  final proxies = [..._maps(rawConfig['proxies'])];
  final proxyByName = {
    for (final proxy in proxies)
      if (proxy['name'] case final String name) name: proxy,
  };
  final groupByName = {
    for (final group in groupList)
      if (group['name'] case final String name) name: group,
  };
  final taken = {
    ...proxyByName.keys,
    ...groupByName.keys,
    ..._builtins,
    ...graph._providers,
    for (final chain in buildable) chain.name,
  };
  String unique(String base) {
    var name = base;
    for (var n = 2; !taken.add(name); n++) {
      name = '$base $n';
    }
    return name;
  }

  for (final chain in buildable) {
    var through = chain.hops.first;
    for (var i = 1; i < chain.hops.length; i++) {
      final hop = chain.hops[i];
      final isExit = i == chain.hops.length - 1;
      final cloneOf = {
        for (final leaf in graph.leavesOf(hop)!)
          leaf: unique(
            isExit ? '$leaf · ${chain.name}' : '$leaf · ${chain.name} $i',
          ),
      };
      for (final MapEntry(key: leaf, value: name) in cloneOf.entries) {
        proxies.add({
          ...proxyByName[leaf]!,
          'name': name,
          'dialer-proxy': through,
        });
      }
      final source = groupByName[hop];
      if (isExit) {
        groupList.add(_groupOf(chain.name, source, cloneOf));
      } else if (source == null) {
        through = cloneOf.values.single;
      } else {
        final name = unique('${chain.name} · $i');
        groupList.add({..._groupOf(name, source, cloneOf), 'hidden': true});
        through = name;
      }
    }
  }
  rawConfig['proxies'] = proxies;
  rawConfig['proxy-groups'] = groupList;
}

/// `include-all` would pick the clones up, so it is listed out beforehand.
List<Map>? _pinIncludeAll(ProxyChainGraph graph, Iterable<Map> groups) {
  final pinned = <Map>[];
  for (final group in groups) {
    final name = group['name'];
    final includeAll = group['include-all'] == true;
    if (name is! String ||
        !(includeAll || group['include-all-proxies'] == true)) {
      pinned.add(group);
      continue;
    }
    final members = graph.membersOf(name);
    if (members == null) {
      return null;
    }
    final usesProviders =
        includeAll ||
        group['include-all-providers'] == true ||
        _strings(group['use']).isNotEmpty;
    pinned.add({
      for (final MapEntry(:key, :value) in group.entries)
        if (key != 'include-all' && key != 'include-all-proxies') key: value,
      if (includeAll) 'include-all-providers': true,
      'proxies': members.isEmpty && !usesProviders
          ? [_string(group['empty-fallback']) ?? 'COMPATIBLE']
          : members,
    });
  }
  return pinned;
}

Map<String, Object?> _groupOf(
  String name,
  Map? source,
  Map<String, String> cloneOf,
) {
  final type = source?['type'];
  final keptType = type is String && _groupTypes.contains(type)
      ? type
      : 'select';
  final defaultSelected = cloneOf[source?['default-selected']];
  return {
    if (source != null)
      for (final MapEntry(:key, :value) in source.entries)
        if (key is String && !_membershipKeys.contains(key)) key: value,
    'name': name,
    'type': keptType,
    'proxies': cloneOf.values.toList(),
    'default-selected': ?defaultSelected,
  };
}

List<RegExp>? _patterns(String? source) {
  if (source == null) {
    return const [];
  }
  try {
    return [for (final pattern in source.split('`')) RegExp(pattern)];
  } on FormatException {
    return null;
  }
}

/// Go sorts strings by their UTF-8 bytes, as mihomo orders `include-all`.
int _compareBytes(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) {
      return x[i] - y[i];
    }
  }
  return x.length - y.length;
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Iterable<Map> _maps(Object? value) =>
    value is List ? value.whereType<Map>() : const [];

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
