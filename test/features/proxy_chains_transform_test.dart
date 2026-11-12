import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/proxy_chains/proxy_chains.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, Object?> _config() => {
  'proxies': <Map<String, Object?>>[
    {'name': 'DE', 'type': 'vless', 'server': 'de.example'},
    {'name': 'NL-1', 'type': 'vless', 'server': 'nl1.example'},
    {'name': 'NL-2', 'type': 'trojan', 'server': 'nl2.example'},
    {'name': 'FI', 'type': 'ss', 'server': 'fi.example'},
  ],
  'proxy-groups': <Map<String, Object?>>[
    {
      'name': 'Auto',
      'type': 'url-test',
      'proxies': ['DE', 'FI'],
      'url': 'https://www.gstatic.com/generate_204',
      'interval': 300,
    },
    {
      'name': 'Netherlands',
      'type': 'url-test',
      'proxies': ['NL-1', 'NL-2'],
      'url': 'https://cp.cloudflare.com',
      'interval': 120,
      'tolerance': 50,
    },
    {
      'name': 'Remote',
      'type': 'select',
      'use': ['provider'],
    },
    {
      'name': 'Nested',
      'type': 'select',
      'proxies': ['Netherlands', 'DIRECT'],
    },
  ],
};

Map<String, Object?> _chain(
  String name,
  List<String> hops, {
  bool enabled = true,
  String? id,
}) => ProxyChain(
  id: id ?? name,
  name: name,
  hops: hops,
  enabled: enabled,
).toJson();

List<Map> _proxies(Map config) => (config['proxies'] as List).cast<Map>();

List<Map> _groups(Map config) => (config['proxy-groups'] as List).cast<Map>();

Map _named(List<Map> items, String name) =>
    items.singleWhere((item) => item['name'] == name);

void main() {
  test('the profile build writes a chain into the config it applies', () async {
    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 1,
        rawConfig: {
          ..._config(),
          'rules': ['MATCH,Auto'],
        },
        realPatchConfig: const PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash-Test',
        proxyChains: [
          _chain('Telegram', ['Auto', 'Netherlands']),
        ],
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;
    final groups = (config['proxy-groups'] as YamlList).cast<Map>();

    expect(_named(groups, 'Telegram')['proxies'], [
      'NL-1 · Telegram',
      'NL-2 · Telegram',
    ]);
    expect(config['rules'], ['MATCH,Auto']);
  });

  test('a group exit dials each of its proxies through the entry', () {
    final config = _config();
    applyProxyChains(config, [
      _chain('Telegram', ['Auto', 'Netherlands']),
    ]);

    final group = _named(_groups(config), 'Telegram');
    expect(group['type'], 'url-test');
    expect(group['url'], 'https://cp.cloudflare.com');
    expect(group['interval'], 120);
    expect(group['tolerance'], 50);
    expect(group['proxies'], ['NL-1 · Telegram', 'NL-2 · Telegram']);
    final clone = _named(_proxies(config), 'NL-2 · Telegram');
    expect(clone['dialer-proxy'], 'Auto');
    expect(clone['server'], 'nl2.example');
    expect(clone['type'], 'trojan');
    expect(_named(_proxies(config), 'NL-2')['dialer-proxy'], isNull);
  });

  test('a node exit becomes a select group of one clone', () {
    final config = _config();
    applyProxyChains(config, [
      _chain('Via DE', ['DE', 'FI']),
    ]);

    final group = _named(_groups(config), 'Via DE');
    expect(group, {
      'name': 'Via DE',
      'type': 'select',
      'proxies': ['FI · Via DE'],
    });
    expect(_named(_proxies(config), 'FI · Via DE')['dialer-proxy'], 'DE');
  });

  test('a middle group hop dials through a hidden group of its clones', () {
    final config = _config();
    applyProxyChains(config, [
      _chain('Three', ['DE', 'Netherlands', 'FI']),
    ]);

    final middle = _named(_groups(config), 'Three · 1');
    expect(middle['hidden'], true);
    expect(middle['proxies'], ['NL-1 · Three 1', 'NL-2 · Three 1']);
    expect(_named(_proxies(config), 'NL-1 · Three 1')['dialer-proxy'], 'DE');
    expect(_named(_proxies(config), 'FI · Three')['dialer-proxy'], 'Three · 1');
    expect(_named(_groups(config), 'Three')['proxies'], ['FI · Three']);
  });

  test('a middle node hop is dialed through directly', () {
    final config = _config();
    applyProxyChains(config, [
      _chain('Line', ['Auto', 'DE', 'Netherlands']),
    ]);

    expect(_named(_proxies(config), 'DE · Line 1')['dialer-proxy'], 'Auto');
    expect(
      _named(_proxies(config), 'NL-1 · Line')['dialer-proxy'],
      'DE · Line 1',
    );
    expect(_groups(config).where((g) => g['hidden'] == true), isEmpty);
  });

  test('a nested group exit clones the proxies it reaches', () {
    final config = _config();
    applyProxyChains(config, [
      _chain('Deep', ['DE', 'Nested']),
    ]);

    expect(_named(_groups(config), 'Deep')['proxies'], [
      'NL-1 · Deep',
      'NL-2 · Deep',
    ]);
  });

  test('chains that cannot be built leave the config alone', () {
    final config = _config();
    final before = _config();
    applyProxyChains(config, [
      _chain('Missing', ['Auto', 'Gone']),
      _chain('Provider', ['Auto', 'Remote']),
      _chain('Twice', ['DE', 'DE']),
      _chain('Auto', ['DE', 'FI']),
      _chain('Off', ['DE', 'FI'], enabled: false),
      _chain('Long', ['DE', 'FI', 'NL-1', 'NL-2']),
    ]);

    expect(config, before);
  });

  test('a provider-backed entry is dialed through as it is', () {
    final config = _config();
    applyProxyChains(config, [
      _chain('From remote', ['Remote', 'FI']),
    ]);

    expect(
      _named(_proxies(config), 'FI · From remote')['dialer-proxy'],
      'Remote',
    );
  });

  test('clone names step around names the profile already has', () {
    final config = _config();
    (config['proxies']! as List).add(<String, Object?>{
      'name': 'FI · A',
      'type': 'ss',
    });
    applyProxyChains(config, [
      _chain('A', ['DE', 'FI']),
      _chain('A', ['Auto', 'FI'], id: 'second'),
    ]);

    expect(_named(_groups(config), 'A')['proxies'], ['FI · A 2']);
    expect(_groups(config).where((g) => g['name'] == 'A'), hasLength(1));
  });

  test('the graph names what is wrong with a chain', () {
    final graph = ProxyChainGraph.fromRaw(_config());
    ProxyChainIssueKind? kindOf(List<String> hops, [String name = 'C']) {
      final chain = ProxyChain(id: 'c', name: name, hops: hops);
      return graph.issuesOf([chain])['c']?.kind;
    }

    expect(kindOf(['Auto', 'Netherlands']), isNull);
    expect(kindOf(['Auto', 'Gone']), ProxyChainIssueKind.missingHop);
    expect(kindOf(['Auto', 'Remote']), ProxyChainIssueKind.providerHop);
    expect(kindOf(['FI', 'FI']), ProxyChainIssueKind.repeatedHop);
    expect(kindOf(['DE', 'FI'], 'Auto'), ProxyChainIssueKind.nameTaken);
    expect(kindOf(['DE', 'FI'], 'DIRECT'), ProxyChainIssueKind.nameTaken);
    expect(kindOf(['DE', 'FI'], 'GLOBAL'), ProxyChainIssueKind.nameTaken);
  });

  test('a direct proxy past the entry would skip the hops before it', () {
    final config = _config();
    (config['proxies']! as List).add(<String, Object?>{
      'name': 'Bypass',
      'type': 'direct',
    });
    final graph = ProxyChainGraph.fromRaw(config);

    expect(
      graph.issuesOf([
        const ProxyChain(id: 'c', name: 'C', hops: ['Auto', 'Bypass']),
      ])['c']?.kind,
      ProxyChainIssueKind.unchainableHop,
    );
    expect(graph.isChainable('Bypass'), isFalse);
    expect(graph.isChainable('Netherlands'), isTrue);
  });

  test('a provider name or a later chain keeps its name from a clone', () {
    final config = _config()
      ..['proxy-providers'] = {
        'feed': {'type': 'http', 'url': 'https://example.com'},
      };
    applyProxyChains(config, [
      _chain('A', ['DE', 'FI']),
      _chain('feed', ['DE', 'FI']),
      _chain('FI · A', ['Auto', 'NL-1']),
    ]);

    final names = [for (final group in _groups(config)) group['name']];
    expect(names, containsAll(['A', 'FI · A']));
    expect(names, isNot(contains('feed')));
    expect(_named(_groups(config), 'A')['proxies'], ['FI · A 2']);
  });

  test('include-all groups keep the members they had before the clones', () {
    final config = _config()
      ..['proxy-providers'] = {
        'feed': {'type': 'http', 'url': 'https://example.com'},
      };
    (config['proxy-groups']! as List).addAll(<Map<String, Object?>>[
      {'name': 'Every', 'type': 'select', 'include-all-proxies': true},
      {'name': 'Both', 'type': 'select', 'include-all': true, 'filter': 'NL'},
    ]);
    applyProxyChains(config, [
      _chain('Loop', ['Every', 'FI']),
    ]);

    final every = _named(_groups(config), 'Every');
    expect(every['proxies'], ['DE', 'FI', 'NL-1', 'NL-2']);
    expect(every.containsKey('include-all-proxies'), isFalse);
    final both = _named(_groups(config), 'Both');
    expect(both['proxies'], ['NL-1', 'NL-2']);
    expect(both['include-all-providers'], true);
    expect(both.containsKey('include-all'), isFalse);
    expect(_named(_proxies(config), 'FI · Loop')['dialer-proxy'], 'Every');
  });

  test('a hop resolves members the way mihomo filters them', () {
    final config = _config();
    (config['proxy-groups']! as List).addAll(<Map<String, Object?>>[
      {
        'name': 'Trimmed',
        'type': 'select',
        'proxies': ['FI', 'NL-1'],
        'exclude-filter': 'NL',
      },
      {
        'name': 'Typed',
        'type': 'select',
        'include-all-proxies': true,
        'exclude-type': 'Shadowsocks|Trojan',
      },
      {
        'name': 'Mixed',
        'type': 'select',
        'proxies': ['FI'],
        'use': ['feed'],
      },
    ]);
    final graph = ProxyChainGraph.fromRaw(config);

    expect(graph.leavesOf('Trimmed'), ['FI']);
    expect(graph.leavesOf('Typed'), ['DE', 'NL-1']);
    expect(graph.leavesOf('Mixed'), isNull);
  });

  test('a rebuilt group keeps its options; only a selector has a default', () {
    final config = _config();
    (config['proxy-groups']! as List).add(<String, Object?>{
      'name': 'Balance',
      'type': 'load-balance',
      'proxies': ['NL-1', 'NL-2'],
      'strategy': 'consistent-hashing',
      'hash-key': 'in-user',
      'disable-udp': true,
      'default-selected': 'NL-2',
      'url': 'https://cp.cloudflare.com',
    });
    applyProxyChains(config, [
      _chain('LB', ['DE', 'Balance']),
    ]);

    final group = _named(_groups(config), 'LB');
    expect(group['hash-key'], 'in-user');
    expect(group['disable-udp'], true);
    expect(group['strategy'], 'consistent-hashing');
    expect(group.containsKey('default-selected'), isFalse);
  });

  test('a malformed stored chain is dropped, not shortened', () {
    expect(
      ProxyChain.fromJson({
        'id': 'a',
        'name': 'A',
        'hops': ['DE', null, 'FI'],
      }),
      isNull,
    );
    expect(
      ProxyChain.fromJson({
        'id': 'a',
        'name': ' ',
        'hops': ['DE', 'FI'],
      }),
      isNull,
    );
    expect(
      ProxyChain.fromJson({
        'id': 'a',
        'name': 'A',
        'hops': ['DE', 'FI'],
        'enabled': 'yes',
      }),
      isNull,
    );
    expect(
      ProxyChain.fromJson({
        'id': 'a',
        'name': 'A',
        'hops': ['DE', 'FI'],
      })?.enabled,
      isTrue,
    );
  });

  test(
    'the graph is resolved where it is built and crosses isolates',
    () async {
      final graph = await compute(ProxyChainGraph.fromRaw, _config());

      expect(graph.isChainable('Netherlands'), isTrue);
      expect(graph.isChainable('Remote'), isFalse);
      expect(graph.leavesOf('Nested'), ['NL-1', 'NL-2']);
    },
  );

  test('an include-all group with no match and no providers keeps its '
      'fallback, and an inline-only one can be a hop', () {
    final config = _config();
    (config['proxy-groups']! as List).addAll(<Map<String, Object?>>[
      {
        'name': 'Nothing',
        'type': 'select',
        'include-all': true,
        'filter': 'ZZ',
      },
      {'name': 'Inline', 'type': 'select', 'include-all': true, 'filter': 'NL'},
    ]);
    applyProxyChains(config, [
      _chain('Via inline', ['DE', 'Inline']),
    ]);

    final nothing = _named(_groups(config), 'Nothing');
    expect(nothing['proxies'], ['COMPATIBLE']);
    expect(nothing.containsKey('include-all-providers'), isFalse);
    expect(_named(_groups(config), 'Via inline')['proxies'], [
      'NL-1 · Via inline',
      'NL-2 · Via inline',
    ]);
  });

  test('mihomo inline flags read as Dart options', () {
    final config = _config();
    (config['proxy-groups']! as List).add(<String, Object?>{
      'name': 'Folded',
      'type': 'select',
      'include-all-proxies': true,
      'filter': '(?i)nl',
    });
    final graph = ProxyChainGraph.fromRaw(config);

    expect(graph.leavesOf('Folded'), ['NL-1', 'NL-2']);
    expect(graph.unpinnable, isNull);
  });

  test('a filter Dart cannot read is reported, not skipped', () {
    final config = _config();
    (config['proxy-groups']! as List).add(<String, Object?>{
      'name': 'Odd',
      'type': 'select',
      'include-all-proxies': true,
      'filter': '(?x)nl',
    });
    final before = _config()..['proxy-groups'] = config['proxy-groups'];
    final graph = ProxyChainGraph.fromRaw(config);
    final chain = ProxyChain.fromJson(_chain('C', ['Auto', 'Netherlands']))!;

    expect(graph.issuesOf([chain])[chain.id], (
      kind: ProxyChainIssueKind.unreadableFilter,
      name: 'Odd',
    ));
    applyProxyChains(config, [chain.toJson()]);
    expect(config, before);
  });

  test('an unreadable exclusion only rules out its own group as a hop', () {
    final config = _config();
    (config['proxy-groups']! as List).add(<String, Object?>{
      'name': 'Odd',
      'type': 'select',
      'proxies': ['FI'],
      'exclude-filter': '(?x)FI',
    });
    final graph = ProxyChainGraph.fromRaw(config);
    final odd = ProxyChain.fromJson(_chain('A', ['DE', 'Odd']))!;
    final fine = ProxyChain.fromJson(_chain('B', ['DE', 'Netherlands']))!;

    expect(graph.issuesOf([odd, fine]), {
      odd.id: (kind: ProxyChainIssueKind.unreadableFilter, name: 'Odd'),
    });
  });

  test('a nested default pick starts the chain on its clone', () {
    final config = _config();
    (config['proxy-groups']! as List).addAll(<Map<String, Object?>>[
      {
        'name': 'First',
        'type': 'select',
        'proxies': ['FI'],
      },
      {
        'name': 'Preferred',
        'type': 'select',
        'proxies': ['NL-2', 'NL-1'],
        'default-selected': 'NL-1',
      },
      {
        'name': 'Exit',
        'type': 'select',
        'proxies': ['First', 'Preferred'],
        'default-selected': 'Preferred',
      },
    ]);
    applyProxyChains(config, [
      _chain('C', ['DE', 'Exit']),
    ]);

    final group = _named(_groups(config), 'C');
    expect(group['proxies'], ['FI · C', 'NL-2 · C', 'NL-1 · C']);
    expect(group['default-selected'], 'NL-1 · C');
  });
}
