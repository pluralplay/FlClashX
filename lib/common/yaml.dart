import 'package:fl_clash/common/yaml_writer.dart';
import 'package:yaml/yaml.dart';

class Yaml {
  static Yaml? _instance;

  Yaml._internal();

  factory Yaml() {
    _instance ??= Yaml._internal();
    return _instance!;
  }

  String encode(Object? value) {
    return writeYaml(value);
  }
}

final yaml = Yaml();

/// Applies `<<` merge keys as mihomo does; package:yaml keeps them as keys.
Object? loadPlainYaml(String content) =>
    plainYaml(loadYaml(content), applyMergeKeys: true);

/// An alias repeats the node it names wherever it appears, so a few lines of
/// nested aliases can stand for billions of nodes; past these bounds a
/// document is refused as unreadable instead of filling memory.
const _maxPlainYamlNodes = 2000000;
const _maxPlainYamlDepth = 512;

Object? plainYaml(Object? node, {bool applyMergeKeys = false}) =>
    _PlainYaml(applyMergeKeys: applyMergeKeys).convert(node, 0);

final class _PlainYaml {
  _PlainYaml({required this.applyMergeKeys});

  final bool applyMergeKeys;
  var _nodes = 0;

  Object? convert(Object? node, int depth) {
    if (++_nodes > _maxPlainYamlNodes || depth > _maxPlainYamlDepth) {
      throw const FormatException('The YAML expands past what can be read');
    }
    return switch (node) {
      YamlMap() => _map(node, depth + 1),
      YamlList() => [for (final item in node) convert(item, depth + 1)],
      _ => node,
    };
  }

  Map<String, Object?> _map(YamlMap node, int depth) {
    final map = <String, Object?>{};
    final merged = <Object?>[];
    for (final MapEntry(:key, :value) in node.entries) {
      if (applyMergeKeys && key == '<<') {
        merged.addAll(value is YamlList ? value : [value]);
      } else {
        map[key.toString()] = convert(value, depth);
      }
    }
    for (final item in merged) {
      if (convert(item, depth) case final Map<String, Object?> source) {
        for (final MapEntry(:key, :value) in source.entries) {
          map.putIfAbsent(key, () => value);
        }
      }
    }
    return map;
  }
}
