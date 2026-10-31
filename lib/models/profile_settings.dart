import 'package:collection/collection.dart';
import 'package:fl_clash/common/cidr.dart';
import 'package:fl_clash/enum/enum.dart';

import 'clash_config.dart';
import 'config.dart';

/// mihomo takes a list of `user:pass` entries; the app keeps one account, the
/// first, and an empty or unreadable list leaves authentication off.
AuthenticationProps authenticationFrom(Object? value) {
  final entries = value is List ? value.whereType<String>() : const <String>[];
  for (final entry in entries) {
    final colon = entry.indexOf(':');
    if (colon > 0) {
      return AuthenticationProps(
        enable: true,
        username: entry.substring(0, colon).trim(),
        password: entry.substring(colon + 1).trim(),
      );
    }
  }
  return const AuthenticationProps();
}

/// [current] with the keys below taken from [config], the decoded profile,
/// where [present] names them, and reset to the app default where it does
/// not; `mode` and `tun.enable` are only ever set, never reset.
/// The tun's app and route lists feed Android's VPN, not the core.
PatchClashConfig syncProfileSettings(
  PatchClashConfig current,
  Map<String, dynamic> config,
  Iterable<String> present, {
  List<Mode> modes = Mode.values,
}) {
  final named = present.toSet();
  const defaults = PatchClashConfig();
  var next = current.copyWith(
    mixedPort: defaults.mixedPort,
    port: defaults.port,
    socksPort: defaults.socksPort,
    redirPort: defaults.redirPort,
    tproxyPort: defaults.tproxyPort,
    allowLan: defaults.allowLan,
    ipv6: defaults.ipv6,
    logLevel: defaults.logLevel,
    findProcessMode: defaults.findProcessMode,
    interfaceNameMode: defaults.interfaceNameMode,
    interfaceName: defaults.interfaceName,
    routingMark: defaults.routingMark,
    tcpConcurrent: defaults.tcpConcurrent,
    unifiedDelay: defaults.unifiedDelay,
    keepAliveInterval: defaults.keepAliveInterval,
    keepAliveIdle: defaults.keepAliveIdle,
    disableKeepAlive: defaults.disableKeepAlive,
    externalController: defaults.externalController,
    secret: defaults.secret,
    geodataLoader: defaults.geodataLoader,
    geoAutoUpdate: defaults.geoAutoUpdate,
    geoUpdateInterval: defaults.geoUpdateInterval,
    geoXUrl: defaults.geoXUrl,
    globalUa: defaults.globalUa,
    tun: current.tun.copyWith(
      device: defaults.tun.device,
      stack: defaults.tun.stack,
      mtu: defaults.tun.mtu,
      congestionController: defaults.tun.congestionController,
      includePackage: defaults.tun.includePackage,
      excludePackage: defaults.tun.excludePackage,
      routeAddress: defaults.tun.routeAddress,
      routeExcludeAddress: defaults.tun.routeExcludeAddress,
    ),
  );
  T? read<T>(String key) {
    if (!named.contains(key)) {
      return null;
    }
    final tun = config['tun'];
    final value = key.startsWith('tun.')
        ? (tun is Map ? tun[key.substring(4)] : null)
        : config[key];
    return value is T ? value : null;
  }

  int? port(String key) {
    final value = read<num>(key)?.toInt();
    return value != null && value >= 0 && value <= 65535 ? value : null;
  }

  T? enumNamed<T extends Enum>(String key, List<T> values) {
    final value = read<String>(key)?.toLowerCase();
    return values.firstWhereOrNull((item) => item.name.toLowerCase() == value);
  }

  next = next.copyWith(
    mixedPort: port('mixed-port') ?? next.mixedPort,
    port: port('port') ?? next.port,
    socksPort: port('socks-port') ?? next.socksPort,
    redirPort: port('redir-port') ?? next.redirPort,
    tproxyPort: port('tproxy-port') ?? next.tproxyPort,
    allowLan: read<bool>('allow-lan') ?? next.allowLan,
    ipv6: read<bool>('ipv6') ?? next.ipv6,
    logLevel: enumNamed('log-level', LogLevel.values) ?? next.logLevel,
    routingMark: read<num>('routing-mark')?.toInt() ?? next.routingMark,
    tcpConcurrent: read<bool>('tcp-concurrent') ?? next.tcpConcurrent,
    unifiedDelay: read<bool>('unified-delay') ?? next.unifiedDelay,
    keepAliveInterval:
        read<num>('keep-alive-interval')?.toInt() ?? next.keepAliveInterval,
    keepAliveIdle: read<num>('keep-alive-idle')?.toInt() ?? next.keepAliveIdle,
    disableKeepAlive: read<bool>('disable-keep-alive') ?? next.disableKeepAlive,
    geoAutoUpdate: read<bool>('geo-auto-update') ?? next.geoAutoUpdate,
    geoUpdateInterval:
        read<num>('geo-update-interval')?.toInt() ?? next.geoUpdateInterval,
    geodataLoader:
        enumNamed('geodata-loader', GeodataLoader.values) ?? next.geodataLoader,
  );
  final mode = enumNamed('mode', Mode.values);
  if (mode != null && modes.contains(mode)) {
    next = next.copyWith(mode: mode);
  }
  final findProcess = read<String>('find-process-mode')?.toLowerCase();
  if (findProcess != null) {
    next = next.copyWith(
      findProcessMode: findProcess == 'off'
          ? FindProcessMode.off
          : FindProcessMode.always,
    );
  }
  final interfaceName = read<String>('interface-name');
  if (interfaceName != null) {
    next = next.copyWith(
      interfaceNameMode: interfaceName.isEmpty
          ? InterfaceNameMode.clear
          : InterfaceNameMode.custom,
      interfaceName: interfaceName,
    );
  }
  final controller = read<String>('external-controller');
  if (controller != null) {
    next = next.copyWith(externalController: controller.trim());
  }
  final secret = read<String>('secret');
  if (secret != null) {
    next = next.copyWith(secret: secret);
  }
  final globalUa = read<String>('global-ua');
  if (globalUa != null) {
    next = next.copyWith(globalUa: globalUa.isEmpty ? null : globalUa);
  }
  final geoXUrl = read<Map>('geox-url');
  if (geoXUrl != null) {
    next = next.copyWith(
      geoXUrl: {
        for (final resource in GeoResource.values)
          resource: switch (geoXUrl[resource.jsonKey]) {
            final String url when url.isNotEmpty => url,
            _ => next.geoXUrl[resource] ?? defaultGeoXUrl[resource]!,
          },
      },
    );
  }
  List<String>? strings(String key, bool Function(String) valid) => read<List>(
    key,
  )?.whereType<String>().map((item) => item.trim()).where(valid).toList();

  final tunDevice = read<String>('tun.device');
  final mtu = read<num>('tun.mtu')?.toInt();
  final congestion = read<String>('tun.congestion-controller')?.toLowerCase();
  next = next.copyWith(
    tun: next.tun.copyWith(
      enable: read<bool>('tun.enable') ?? next.tun.enable,
      device: tunDevice == null || tunDevice.isEmpty
          ? next.tun.device
          : tunDevice,
      stack: enumNamed('tun.stack', TunStack.values) ?? next.tun.stack,
      mtu: mtu != null && mtu >= minTunMtu && mtu <= maxTunMtu
          ? mtu
          : next.tun.mtu,
      congestionController:
          congestion != null && congestionControllers.contains(congestion)
          ? congestion
          : next.tun.congestionController,
      includePackage:
          strings('tun.include-package', (name) => name.isNotEmpty) ??
          next.tun.includePackage,
      excludePackage:
          strings('tun.exclude-package', (name) => name.isNotEmpty) ??
          next.tun.excludePackage,
      routeAddress:
          strings('tun.route-address', isCidr) ?? next.tun.routeAddress,
      routeExcludeAddress:
          strings('tun.route-exclude-address', isCidr) ??
          next.tun.routeExcludeAddress,
    ),
  );
  return next;
}

extension on GeoResource {
  String get jsonKey => switch (this) {
    GeoResource.MMDB => 'mmdb',
    GeoResource.ASN => 'asn',
    GeoResource.GEOIP => 'geoip',
    GeoResource.GEOSITE => 'geosite',
  };
}
