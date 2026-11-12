import 'dart:convert';

import 'chain.dart';

enum ProxyChainIssueKind {
  missingHop,
  providerHop,
  unchainableHop,
  unreadableFilter,
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
};

typedef _Resolved = ({List<String>? leaves, ProxyChainIssue? issue});

/// One profile's outbounds, with group members resolved as mihomo does. All
/// the walking happens as it is built, off the UI isolate.
class ProxyChainGraph {
  ProxyChainGraph._({
    required this.proxyTypes,
    required this.groupTypes,
    required Set<String> groupNames,
    required Set<String> providers,
    required Map<String, String?> defaults,
    required Map<String, List<String>> pinned,
    required Map<String, List<String>> leaves,
    required Map<String, ProxyChainIssue> hopIssues,
    required this.unpinnable,
  }) : _groupNames = groupNames,
       _providers = providers,
       _defaults = defaults,
       _pinned = pinned,
       _leaves = leaves,
       _hopIssues = hopIssues;

  factory ProxyChainGraph.fromRaw(Map rawConfig) =>
      _GraphBuilder(rawConfig).build();

  final Map<String, String> proxyTypes;

  /// Visible groups, by name, with their types.
  final Map<String, String> groupTypes;
  final Set<String> _groupNames;
  final Set<String> _providers;
  final Map<String, String?> _defaults;
  final Map<String, List<String>> _pinned;
  final Map<String, List<String>> _leaves;
  final Map<String, ProxyChainIssue> _hopIssues;

  /// An `include-all` group whose filter Dart cannot read, so the clones
  /// cannot be kept out of it.
  final String? unpinnable;

  bool has(String name) =>
      proxyTypes.containsKey(name) || _groupNames.contains(name);

  bool _reserved(String name) =>
      has(name) || _builtins.contains(name) || _providers.contains(name);

  List<String>? leavesOf(String name) =>
      proxyTypes.containsKey(name) ? [name] : _leaves[name];

  bool isChainable(String name) => has(name) && !_hopIssues.containsKey(name);

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
      if (_hopIssues[hop] case final ProxyChainIssue issue) {
        return issue;
      }
    }
    return null;
  }

  /// By chain id; a name goes to the first enabled chain that can take it.
  Map<String, ProxyChainIssue> issuesOf(Iterable<ProxyChain> chains) {
    final unpinnable = this.unpinnable;
    final names = <String>{};
    final issues = <String, ProxyChainIssue>{};
    for (final chain in chains) {
      final issue =
          (unpinnable == null
              ? null
              : (
                  kind: ProxyChainIssueKind.unreadableFilter,
                  name: unpinnable,
                )) ??
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

  /// The leaf a selector starts on: its default pick, followed down.
  String? _defaultLeafOf(String name, Set<String> visiting) {
    if (proxyTypes.containsKey(name)) {
      return name;
    }
    if (!_defaults.containsKey(name) || !visiting.add(name)) {
      return null;
    }
    final pick = _defaults[name];
    return pick == null ? null : _defaultLeafOf(pick, visiting);
  }
}

class _GraphBuilder {
  _GraphBuilder(Map rawConfig)
    : _rawGroups = {
        for (final group in _maps(rawConfig['proxy-groups']))
          if (group['name'] case final String name) name: group,
      },
      _proxyTypes = {
        for (final proxy in _maps(rawConfig['proxies']))
          if (proxy['name'] case final String name)
            name: _string(proxy['type'])?.toLowerCase() ?? '',
      },
      _providers = {
        if (rawConfig['proxy-providers'] case final Map providers)
          ...providers.keys.whereType<String>(),
      };

  final Map<String, Map> _rawGroups;
  final Map<String, String> _proxyTypes;
  final Set<String> _providers;
  final _members = <String, List<String>>{};
  final _unreadable = <String>{};
  final _resolved = <String, _Resolved>{};
  late final _allProxies = [..._proxyTypes.keys]..sort(_compareBytes);

  bool _usesProviders(Map group) =>
      _strings(group['use']).isNotEmpty ||
      (_providers.isNotEmpty &&
          (group['include-all'] == true ||
              group['include-all-providers'] == true));

  bool _includesProxies(Map group) =>
      group['include-all'] == true || group['include-all-proxies'] == true;

  /// The inline proxies `include-all` brings in, before any exclusion.
  List<String>? _included(Map group) {
    if (!_includesProxies(group)) {
      return const [];
    }
    final filters = _patterns(group['filter']);
    if (filters == null) {
      return null;
    }
    return filters.isEmpty
        ? _allProxies
        : [
            for (final proxy in _allProxies)
              if (filters.any((filter) => filter.hasMatch(proxy))) proxy,
          ];
  }

  void _resolveMembers(String name, Map group) {
    final included = _included(group);
    final excluded = _patterns(group['exclude-filter']);
    if (included == null || excluded == null) {
      _unreadable.add(name);
      return;
    }
    final excludedTypes = {
      for (final type in (_string(group['exclude-type']) ?? '').split('|'))
        if (type.trim().isNotEmpty) type.trim().toLowerCase(),
    };
    _members[name] = [
      for (final member in [..._strings(group['proxies']), ...included])
        if (!excluded.any((filter) => filter.hasMatch(member)) &&
            !excludedTypes.contains(_adapterTypeOf(member)))
          member,
    ];
  }

  String _adapterTypeOf(String name) {
    final type = _proxyTypes[name] ?? _string(_rawGroups[name]?['type']) ?? '';
    return (_adapterTypes[type] ?? type).replaceAll('-', '').toLowerCase();
  }

  _Resolved _resolve(String name, Set<String> visiting) {
    if (_proxyTypes.containsKey(name)) {
      return (leaves: [name], issue: null);
    }
    final cached = _resolved[name];
    if (cached != null) {
      return cached;
    }
    final group = _rawGroups[name];
    if (group == null) {
      return (leaves: const [], issue: null);
    }
    if (!visiting.add(name)) {
      return (leaves: const [], issue: null);
    }
    final _Resolved resolved;
    if (_usesProviders(group)) {
      resolved = (
        leaves: null,
        issue: (kind: ProxyChainIssueKind.providerHop, name: name),
      );
    } else if (_unreadable.contains(name)) {
      resolved = (
        leaves: null,
        issue: (kind: ProxyChainIssueKind.unreadableFilter, name: name),
      );
    } else {
      resolved = _resolveLeaves(_members[name]!, visiting);
    }
    visiting.remove(name);
    return _resolved[name] = resolved;
  }

  _Resolved _resolveLeaves(List<String> members, Set<String> visiting) {
    final found = <String>{};
    for (final member in members) {
      final resolved = _resolve(member, visiting);
      final leaves = resolved.leaves;
      if (leaves == null) {
        return resolved;
      }
      found.addAll(leaves);
    }
    return (leaves: found.toList(), issue: null);
  }

  ProxyChainGraph build() {
    for (final MapEntry(key: name, value: group) in _rawGroups.entries) {
      _resolveMembers(name, group);
    }
    final pinned = <String, List<String>>{};
    String? unpinnable;
    for (final MapEntry(key: name, value: group) in _rawGroups.entries) {
      if (!_includesProxies(group)) {
        continue;
      }
      final included = _included(group);
      if (included == null) {
        unpinnable ??= name;
        continue;
      }
      pinned[name] = [..._strings(group['proxies']), ...included];
    }
    final leaves = <String, List<String>>{};
    final hopIssues = <String, ProxyChainIssue>{};
    for (final name in _rawGroups.keys) {
      final resolved = _resolve(name, <String>{});
      final groupLeaves = resolved.leaves;
      if (groupLeaves == null) {
        hopIssues[name] = resolved.issue!;
        continue;
      }
      leaves[name] = groupLeaves;
      if (groupLeaves.isEmpty || groupLeaves.any(_unchainable)) {
        hopIssues[name] = (
          kind: ProxyChainIssueKind.unchainableHop,
          name: name,
        );
      }
    }
    for (final name in _proxyTypes.keys) {
      if (_unchainable(name)) {
        hopIssues[name] = (
          kind: ProxyChainIssueKind.unchainableHop,
          name: name,
        );
      }
    }
    return ProxyChainGraph._(
      proxyTypes: _proxyTypes,
      groupTypes: {
        for (final MapEntry(:key, :value) in _rawGroups.entries)
          if (value['hidden'] != true) key: _string(value['type']) ?? '',
      },
      groupNames: _rawGroups.keys.toSet(),
      providers: _providers,
      defaults: {
        for (final MapEntry(:key, :value) in _rawGroups.entries)
          if (value['type'] == 'select')
            key:
                _string(value['default-selected']) ??
                _members[key]?.firstOrNull,
      },
      pinned: pinned,
      leaves: leaves,
      hopIssues: hopIssues,
      unpinnable: unpinnable,
    );
  }

  bool _unchainable(String name) =>
      _unchainableTypes.contains(_proxyTypes[name]);
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
  final groupList = [
    for (final group in _maps(rawConfig['proxy-groups'])) _pin(graph, group),
  ];
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
      final defaultLeaf = source == null
          ? null
          : graph._defaultLeafOf(hop, <String>{});
      if (isExit) {
        groupList.add(_groupOf(chain.name, source, cloneOf, defaultLeaf));
      } else if (source == null) {
        through = cloneOf.values.single;
      } else {
        final name = unique('${chain.name} · $i');
        groupList.add({
          ..._groupOf(name, source, cloneOf, defaultLeaf),
          'hidden': true,
        });
        through = name;
      }
    }
  }
  rawConfig['proxies'] = proxies;
  rawConfig['proxy-groups'] = groupList;
}

/// `include-all` would pick the clones up, so it is listed out beforehand;
/// exclusions stay for mihomo to apply as it did.
Map _pin(ProxyChainGraph graph, Map group) {
  final name = group['name'];
  final pinned = name is String ? graph._pinned[name] : null;
  if (pinned == null) {
    return group;
  }
  final includeAll = group['include-all'] == true;
  final usesProviders =
      _strings(group['use']).isNotEmpty ||
      (graph._providers.isNotEmpty &&
          (includeAll || group['include-all-providers'] == true));
  return {
    for (final MapEntry(:key, :value) in group.entries)
      if (key != 'include-all' && key != 'include-all-proxies') key: value,
    if (includeAll && graph._providers.isNotEmpty)
      'include-all-providers': true,
    'proxies': pinned.isEmpty && !usesProviders
        ? [_string(group['empty-fallback']) ?? 'COMPATIBLE']
        : pinned,
  };
}

Map<String, Object?> _groupOf(
  String name,
  Map? source,
  Map<String, String> cloneOf,
  String? defaultLeaf,
) {
  final type = source?['type'];
  final keptType = type is String && _groupTypes.contains(type)
      ? type
      : 'select';
  final defaultSelected = keptType == 'select' ? cloneOf[defaultLeaf] : null;
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

final _leadingFlags = RegExp(r'^\(\?([a-zA-Z]+)\)');

/// mihomo compiles filters with regexp2; its leading inline flags become
/// Dart options, and anything else Dart cannot read is reported as such.
List<RegExp>? _patterns(Object? value) {
  final source = _string(value);
  if (source == null) {
    return const [];
  }
  final patterns = <RegExp>[];
  for (var pattern in source.split('`')) {
    var caseSensitive = true;
    var multiLine = false;
    var dotAll = false;
    final flags = _leadingFlags.firstMatch(pattern);
    if (flags != null) {
      for (final flag in flags.group(1)!.split('')) {
        switch (flag) {
          case 'i':
            caseSensitive = false;
          case 'm':
            multiLine = true;
          case 's':
            dotAll = true;
          default:
            return null;
        }
      }
      pattern = pattern.substring(flags.end);
    }
    if (!_readsAlike(pattern)) {
      return null;
    }
    try {
      patterns.add(
        RegExp(
          pattern,
          caseSensitive: caseSensitive,
          multiLine: multiLine,
          dotAll: dotAll,
          unicode: true,
        ),
      );
    } on FormatException {
      return null;
    }
  }
  return patterns;
}

/// Escapes that mean something else in Dart than in regexp2's .NET syntax.
const _divergentEscapes = {
  'A',
  'Z',
  'z',
  'G',
  'p',
  'P',
  'e',
  'a',
  'w',
  'W',
  'b',
  'B',
  'd',
  'D',
  's',
  'S',
  'k',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
};

bool _readsAlike(String pattern) {
  var inClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == r'\') {
      if (i + 1 < pattern.length &&
          _divergentEscapes.contains(pattern[i + 1])) {
        return false;
      }
      i++;
    } else if (char == '[' && !inClass) {
      inClass = true;
    } else if (char == ']' && inClass) {
      inClass = false;
    } else if (inClass && pattern.startsWith('-[', i)) {
      return false;
    }
  }
  return true;
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
