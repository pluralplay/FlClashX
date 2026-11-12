import 'chain.dart';

enum ProxyChainIssueKind { missingHop, providerHop, repeatedHop, nameTaken }

typedef ProxyChainIssue = ({ProxyChainIssueKind kind, String name});

const _groupTypes = {'select', 'url-test', 'fallback', 'load-balance'};

/// What a measuring group carries over to the group of its clones.
const _groupOptions = [
  'url',
  'interval',
  'tolerance',
  'lazy',
  'timeout',
  'expected-status',
  'max-failed-times',
  'strategy',
];

/// The outbounds a chain can reach in one profile. Only inline proxies can be
/// cloned, so a group's leaves are the inline proxies its `proxies` list
/// reaches; provider members (`use`, `include-all`) are not among them.
class ProxyChainGraph {
  ProxyChainGraph({required this.proxies, required this.groups});

  factory ProxyChainGraph.fromRaw(Map rawConfig) {
    final groups = <String, List<String>>{};
    for (final group in _maps(rawConfig['proxy-groups'])) {
      final name = group['name'];
      if (name is String) {
        groups[name] = _strings(group['proxies']);
      }
    }
    return ProxyChainGraph(
      proxies: {
        for (final proxy in _maps(rawConfig['proxies']))
          if (proxy['name'] case final String name) name,
      },
      groups: groups,
    );
  }

  final Set<String> proxies;
  final Map<String, List<String>> groups;
  final _leaves = <String, List<String>>{};

  bool has(String name) => proxies.contains(name) || groups.containsKey(name);

  bool isGroup(String name) => groups.containsKey(name);

  List<String> leavesOf(String name) => _leavesOf(name, <String>{});

  List<String> _leavesOf(String name, Set<String> visiting) {
    if (proxies.contains(name)) {
      return [name];
    }
    final cached = _leaves[name];
    if (cached != null) {
      return cached;
    }
    final members = groups[name];
    if (members == null || !visiting.add(name)) {
      return const [];
    }
    final leaves = <String>{
      for (final member in members) ..._leavesOf(member, visiting),
    }.toList();
    visiting.remove(name);
    return _leaves[name] = leaves;
  }

  /// Why [chain] cannot be built, given the names already [taken].
  ProxyChainIssue? issueOf(ProxyChain chain, {Set<String>? taken}) {
    for (final hop in chain.hops) {
      if (!has(hop)) {
        return (kind: ProxyChainIssueKind.missingHop, name: hop);
      }
    }
    if (chain.hops.toSet().length != chain.hops.length) {
      return (kind: ProxyChainIssueKind.repeatedHop, name: chain.name);
    }
    for (final hop in chain.hops.skip(1)) {
      if (leavesOf(hop).isEmpty) {
        return (kind: ProxyChainIssueKind.providerHop, name: hop);
      }
    }
    if (has(chain.name) || (taken?.contains(chain.name) ?? false)) {
      return (kind: ProxyChainIssueKind.nameTaken, name: chain.name);
    }
    return null;
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
          when chain.enabled &&
              chain.hops.length >= ProxyChain.minHops &&
              chain.hops.length <= ProxyChain.maxHops)
        chain,
  ];
  if (chains.isEmpty) {
    return;
  }
  final proxies = [..._maps(rawConfig['proxies'])];
  final groupList = [..._maps(rawConfig['proxy-groups'])];
  final proxyByName = {
    for (final proxy in proxies)
      if (proxy['name'] case final String name) name: proxy,
  };
  final groupByName = {
    for (final group in groupList)
      if (group['name'] case final String name) name: group,
  };
  final graph = ProxyChainGraph.fromRaw(rawConfig);
  final taken = {...proxyByName.keys, ...groupByName.keys};
  String unique(String base) {
    var name = base;
    for (var n = 2; !taken.add(name); n++) {
      name = '$base $n';
    }
    return name;
  }

  for (final chain in chains) {
    if (graph.issueOf(chain, taken: taken) != null) {
      continue;
    }
    taken.add(chain.name);
    var through = chain.hops.first;
    for (var i = 1; i < chain.hops.length; i++) {
      final hop = chain.hops[i];
      final isExit = i == chain.hops.length - 1;
      final clones = [
        for (final leaf in graph.leavesOf(hop))
          _clone(
            proxyByName[leaf]!,
            unique(
              isExit ? '$leaf · ${chain.name}' : '$leaf · ${chain.name} $i',
            ),
            through,
            proxies,
          ),
      ];
      final source = groupByName[hop];
      if (isExit) {
        groupList.add(_groupOf(chain.name, source, clones));
      } else if (source == null) {
        through = clones.single;
      } else {
        final name = unique('${chain.name} · $i');
        groupList.add({..._groupOf(name, source, clones), 'hidden': true});
        through = name;
      }
    }
  }
  rawConfig['proxies'] = proxies;
  rawConfig['proxy-groups'] = groupList;
}

String _clone(Map proxy, String name, String through, List<Map> proxies) {
  proxies.add({...proxy, 'name': name, 'dialer-proxy': through});
  return name;
}

Map<String, Object?> _groupOf(String name, Map? source, List<String> members) {
  final type = source?['type'];
  final keptType = type is String && _groupTypes.contains(type)
      ? type
      : 'select';
  return {
    'name': name,
    'type': keptType,
    'proxies': members,
    if (keptType != 'select' && source != null)
      for (final option in _groupOptions)
        if (source.containsKey(option)) option: source[option],
  };
}

Iterable<Map> _maps(Object? value) =>
    value is List ? value.whereType<Map>() : const [];

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
