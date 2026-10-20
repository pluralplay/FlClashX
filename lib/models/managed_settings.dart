import 'clash_config.dart';
import 'provider_headers.dart';

/// Flags of `flclashx-settings` and the app switch each one drives.
const appSwitchSettings = {
  'minimize': 'app.minimizeOnExit',
  'autorun': 'app.autoLaunch',
  'shadowstart': 'app.silentLaunch',
  'autostart': 'app.autoRun',
  'autoupdate': 'app.autoCheckUpdate',
  'openlogs': 'app.openLogs',
  'closeconnections': 'app.closeConnections',
};

/// The config keys a subscription takes over and the user may take back.
const managedClashKeys = {
  'mixed-port',
  'port',
  'socks-port',
  'redir-port',
  'tproxy-port',
  'allow-lan',
  'ipv6',
  'log-level',
  'find-process-mode',
  'interface-name',
  'routing-mark',
  'tcp-concurrent',
  'unified-delay',
  'keep-alive-interval',
  'keep-alive-idle',
  'disable-keep-alive',
  'external-controller',
  'secret',
  'geodata-loader',
  'geo-auto-update',
  'geo-update-interval',
  'geox-url',
  'global-ua',
  'tun.device',
  'tun.stack',
};

String clashSettingKey(String yamlKey) => 'clash.$yamlKey';

/// The lockable keys of each settings page, for its hint.
const generalPageKeys = {
  'app.minimizeOnExit',
  'app.autoLaunch',
  'app.silentLaunch',
  'app.autoRun',
  'app.autoCheckUpdate',
  'app.openLogs',
  'app.closeConnections',
  'clash.allow-lan',
  'clash.ipv6',
  'clash.find-process-mode',
  'clash.tcp-concurrent',
  'clash.unified-delay',
  'clash.geodata-loader',
  'clash.external-controller',
  'clash.secret',
  'clash.log-level',
  'clash.mixed-port',
};

const networkPageKeys = {
  'clash.tun.stack',
  'clash.interface-name',
  'clash.disable-keep-alive',
  'clash.keep-alive-idle',
  'clash.keep-alive-interval',
  'clash.routing-mark',
};

const themePageKeys = {
  'view.app.board',
  'view.app.navbar',
  'view.app.tabs',
  'view.app.glass',
  'view.app.color',
  'view.app.black',
};

const proxiesPageKeys = {
  'view.proxies.type',
  'view.proxies.sort',
  'view.proxies.layout',
  'view.proxies.icon',
  'view.proxies.card',
};

/// The settings a `flclashx-view` header speaks for, by what it names.
Set<String> managedViewKeysOf(ViewRequest? view) {
  if (view == null) {
    return const {};
  }
  return {
    if (view.type != null) 'view.proxies.type',
    if (view.sort != null) 'view.proxies.sort',
    if (view.layout != null) 'view.proxies.layout',
    if (view.icon != null) 'view.proxies.icon',
    if (view.card != null) 'view.proxies.card',
    if (view.board != null) 'view.app.board',
    if (view.floatingNavigationBar != null) 'view.app.navbar',
    if (view.tabAnimation != null) 'view.app.tabs',
    if (view.liquidGlass != null) 'view.app.glass',
    if (view.color != null || view.colorStyle != null) 'view.app.color',
    if (view.pureBlack != null) 'view.app.black',
  };
}

Set<String> managedClashKeysOf(Iterable<String> present) => {
  for (final key in present)
    if (managedClashKeys.contains(key)) clashSettingKey(key),
};

/// [synced] with every setting in [owned] put back as [current] had it.
PatchClashConfig keepOwnedSettings(
  PatchClashConfig current,
  PatchClashConfig synced,
  Set<String> owned,
) {
  var next = synced;
  for (final key in owned) {
    next = switch (key) {
      'clash.mixed-port' => next.copyWith(mixedPort: current.mixedPort),
      'clash.port' => next.copyWith(port: current.port),
      'clash.socks-port' => next.copyWith(socksPort: current.socksPort),
      'clash.redir-port' => next.copyWith(redirPort: current.redirPort),
      'clash.tproxy-port' => next.copyWith(tproxyPort: current.tproxyPort),
      'clash.allow-lan' => next.copyWith(allowLan: current.allowLan),
      'clash.ipv6' => next.copyWith(ipv6: current.ipv6),
      'clash.log-level' => next.copyWith(logLevel: current.logLevel),
      'clash.find-process-mode' => next.copyWith(
        findProcessMode: current.findProcessMode,
      ),
      'clash.interface-name' => next.copyWith(
        interfaceNameMode: current.interfaceNameMode,
        interfaceName: current.interfaceName,
      ),
      'clash.routing-mark' => next.copyWith(routingMark: current.routingMark),
      'clash.tcp-concurrent' => next.copyWith(
        tcpConcurrent: current.tcpConcurrent,
      ),
      'clash.unified-delay' => next.copyWith(
        unifiedDelay: current.unifiedDelay,
      ),
      'clash.keep-alive-interval' => next.copyWith(
        keepAliveInterval: current.keepAliveInterval,
      ),
      'clash.keep-alive-idle' => next.copyWith(
        keepAliveIdle: current.keepAliveIdle,
      ),
      'clash.disable-keep-alive' => next.copyWith(
        disableKeepAlive: current.disableKeepAlive,
      ),
      'clash.external-controller' => next.copyWith(
        externalController: current.externalController,
      ),
      'clash.secret' => next.copyWith(secret: current.secret),
      'clash.geodata-loader' => next.copyWith(
        geodataLoader: current.geodataLoader,
      ),
      'clash.geo-auto-update' => next.copyWith(
        geoAutoUpdate: current.geoAutoUpdate,
      ),
      'clash.geo-update-interval' => next.copyWith(
        geoUpdateInterval: current.geoUpdateInterval,
      ),
      'clash.geox-url' => next.copyWith(geoXUrl: current.geoXUrl),
      'clash.global-ua' => next.copyWith(globalUa: current.globalUa),
      'clash.tun.device' => next.copyWith(
        tun: next.tun.copyWith(device: current.tun.device),
      ),
      'clash.tun.stack' => next.copyWith(
        tun: next.tun.copyWith(stack: current.tun.stack),
      ),
      _ => next,
    };
  }
  return next;
}
