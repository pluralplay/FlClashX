import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Hops in order: the device connects to the first, traffic leaves from the
/// last, and each hop after the first dials through the one before it.
@immutable
class ProxyChain {
  const ProxyChain({
    required this.id,
    required this.name,
    required this.hops,
    this.enabled = true,
  });

  static const minHops = 2;
  static const maxHops = 3;

  final String id;
  final String name;
  final List<String> hops;
  final bool enabled;

  static ProxyChain? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final name = json['name'];
    final hops = json['hops'];
    if (id is! String || name is! String || hops is! List) {
      return null;
    }
    return ProxyChain(
      id: id,
      name: name,
      hops: [
        for (final hop in hops)
          if (hop is String) hop,
      ],
      enabled: json['enabled'] != false,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'hops': hops,
    'enabled': enabled,
  };

  ProxyChain copyWith({String? name, List<String>? hops, bool? enabled}) {
    return ProxyChain(
      id: id,
      name: name ?? this.name,
      hops: hops ?? this.hops,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProxyChain &&
      other.id == id &&
      other.name == name &&
      other.enabled == enabled &&
      const ListEquality<String>().equals(other.hops, hops);

  @override
  int get hashCode => Object.hash(id, name, enabled, Object.hashAll(hops));
}
