import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/proxy_chains/proxy_chains.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, Object?> _config() => {
  'proxies': <Map<String, Object?>>[
    {'name': 'DE', 'type': 'vless', 'server': 'de.example'},
    {'name': 'NL-1', 'type': 'vless', 'server': 'nl1.example'},
    {'name': 'NL-2', 'type': 'trojan', 'server': 'nl2.example'},
    {'name': 'FI', 'type': 'ss', 'server': 'fi.example'},
  ],
  'proxy-groups': [
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
}) => ProxyChain(id: name, name: name, hops: hops, enabled: enabled).toJson();

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
      _chain('A', ['Auto', 'FI']),
    ]);

    expect(_named(_groups(config), 'A')['proxies'], ['FI · A 2']);
    expect(_groups(config).where((g) => g['name'] == 'A'), hasLength(1));
  });

  test('the graph names what is wrong with a chain', () {
    final graph = ProxyChainGraph.fromRaw(_config());
    ProxyChainIssueKind? kindOf(List<String> hops, [String name = 'C']) =>
        graph.issueOf(ProxyChain(id: 'c', name: name, hops: hops))?.kind;

    expect(kindOf(['Auto', 'Netherlands']), isNull);
    expect(kindOf(['Auto', 'Gone']), ProxyChainIssueKind.missingHop);
    expect(kindOf(['Auto', 'Remote']), ProxyChainIssueKind.providerHop);
    expect(kindOf(['FI', 'FI']), ProxyChainIssueKind.repeatedHop);
    expect(kindOf(['DE', 'FI'], 'Auto'), ProxyChainIssueKind.nameTaken);
  });
}
