import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/ui/color.dart';

import 'config.dart';
import 'profile.dart';

const maxAnnouncementLength = 200;

/// A panel's subscription headers, off [Profile.providerHeaders]; a new
/// header is a getter here and nothing else.
class ProviderHeaders {
  const ProviderHeaders(this._headers);

  final Map<String, String> _headers;

  String? text(String name) {
    final value = _headers[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get supportUrl => text('support-url');

  String? get title => _plainOrBase64(text('profile-title'));

  String? get webPageUrl {
    final url = text('profile-web-page-url');
    return url != null && url.isUrl ? url : null;
  }

  bool get deviceLimitReached => _flag('x-hwid-max-devices-reached');

  bool get deviceIdUnsupported => _flag('x-hwid-not-supported');

  bool _flag(String name) => text(name)?.toLowerCase() == 'true';

  /// Hours between automatic updates, when the panel names them.
  Duration? get updateInterval {
    final hours = int.tryParse(text('profile-update-interval') ?? '');
    return hours != null && hours > 0 ? Duration(hours: hours) : null;
  }

  ViewRequest? get view => ViewRequest.parse(text('flclashx-view'));

  /// The standard dashboard's cards, comma-separated; null when none exists.
  List<DashboardWidget>? get dashboardWidgets {
    final raw = text('flclashx-widgets');
    if (raw == null) {
      return null;
    }
    final widgets = dashboardWidgetsNamed(raw.split(','));
    return widgets.isEmpty ? null : widgets;
  }

  PanelBackground? get background =>
      PanelBackground.parse(text('flclashx-background'));

  /// Which of the app switches the panel turns on; the rest it turns off.
  Set<String>? get appSwitches {
    final raw = text('flclashx-settings');
    if (raw == null) {
      return null;
    }
    return {
      for (final item in raw.split(','))
        if (item.trim().isNotEmpty) item.trim().toLowerCase(),
    };
  }

  /// Flags of `flclashx-special`, the panel's one-off behaviours.
  Set<String>? get specials {
    final raw = text('flclashx-special');
    if (raw == null) {
      return null;
    }
    return {
      for (final item in raw.split(','))
        if (item.trim().isNotEmpty) item.trim().toLowerCase(),
    };
  }

  bool get androidSecure => specials?.contains('androidsecure') ?? false;

  bool get widgetEditingDenied => specials?.contains('denywidgets') ?? false;

  /// `flclashx-special: noglobal` takes the Global outbound mode away.
  bool get globalModeAllowed => !(specials?.contains('noglobal') ?? false);

  String? get serviceName => _plainOrBase64(text('flclashx-servicename'));

  String? get serviceLogo {
    final url = _plainOrBase64(text('flclashx-servicelogo'));
    return url != null && url.isUrl ? url : null;
  }

  String? get serverGroup => _plainOrBase64(text('flclashx-serverinfo'));

  /// Plain or base64 (optionally `base64:`-prefixed), whole.
  String? get fullAnnouncement {
    final raw = text('announce');
    if (raw == null) {
      return null;
    }
    final decoded = _decodeAnnouncement(raw).trim();
    return decoded.isEmpty ? null : decoded;
  }

  /// [fullAnnouncement] cut to [maxAnnouncementLength] characters.
  String? get announcement {
    final decoded = fullAnnouncement;
    if (decoded == null) {
      return null;
    }
    final runes = decoded.runes;
    if (runes.length <= maxAnnouncementLength) {
      return decoded;
    }
    final cut = String.fromCharCodes(runes.take(maxAnnouncementLength));
    return '${cut.trimRight()}…';
  }

  LinkOffer? get buyPlan => LinkOffer.parse(text('flclashx-buyplan'));

  LinkOffer? get buyTraffic => LinkOffer.parse(text('flclashx-buytraffic'));

  /// The panel's other hosts in the order to try them, each a host,
  /// `host:port` or a full origin.
  List<String> get fallbackHosts => (text('flclashx-newdomain') ?? '')
      .split(',')
      .map((host) => host.trim())
      .where((host) => host.isNotEmpty)
      .take(maxFallbackHosts)
      .toList();

  /// [url] on each fallback host, keeping its path, query and credentials;
  /// the scheme and port follow the host when it names them.
  List<Uri> fallbackUrlsOf(Uri url) {
    final urls = <Uri>[];
    for (final host in fallbackHosts) {
      final moved = _moveHost(url, host);
      if (moved == null) {
        continue;
      }
      if (_sameOrigin(moved, url) || urls.any((u) => _sameOrigin(u, moved))) {
        continue;
      }
      urls.add(moved);
    }
    return urls;
  }
}

const maxFallbackHosts = 5;

final _hostName = RegExp(r'^[A-Za-z0-9.\-]+$');

Uri? _moveHost(Uri url, String host) {
  if (!url.hasScheme || url.host.isEmpty) {
    return null;
  }
  final origin = Uri.tryParse(
    host.contains('://') ? host : '${url.scheme}://$host',
  );
  if (origin == null ||
      origin.host.isEmpty ||
      !_hostName.hasMatch(origin.host) ||
      origin.path.isNotEmpty && origin.path != '/' ||
      origin.hasQuery) {
    return null;
  }
  final sameScheme = origin.scheme == url.scheme;
  return url.replace(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort
        ? origin.port
        : sameScheme
        ? url.port
        : null,
  );
}

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

/// Base64 when it decodes to text, else the value as given.
String? _plainOrBase64(String? raw) {
  if (raw == null) {
    return null;
  }
  const prefix = 'base64:';
  final encoded = raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
  try {
    final decoded = utf8
        .decode(base64.decode(base64.normalize(encoded.trim())))
        .trim();
    return decoded.isEmpty ? null : decoded;
  } on FormatException {
    return raw;
  }
}

String _decodeAnnouncement(String raw) {
  const prefix = 'base64:';
  final encoded = raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
  try {
    return utf8.decode(base64.decode(base64.normalize(encoded.trim())));
  } on FormatException {
    return raw.startsWith(prefix) ? '' : raw;
  }
}

/// `key:value;...` over the look of the app. `proxies.*` keys shape the
/// proxies page: `type` list|tab, `sort` none|delay|name, `layout`
/// loose|standard|tight, `icon` filled|plain|hidden, `card`
/// loose|standard|compact. `app.*` keys shape the app: `board`
/// extended|standard, `navbar` floating|docked, `tabs` slide|fade, `glass`
/// none|standard|ultra, `color` RRGGBB|AARRGGBB, `style`
/// vivid|tinted|soft|monochrome, `black` true|false.
class ViewRequest {
  const ViewRequest({
    this.type,
    this.sort,
    this.layout,
    this.icon,
    this.card,
    this.board,
    this.floatingNavigationBar,
    this.tabAnimation,
    this.liquidGlass,
    this.color,
    this.colorStyle,
    this.pureBlack,
  });

  final ProxiesType? type;
  final ProxiesSortType? sort;
  final ProxiesLayout? layout;
  final ProxiesIconStyle? icon;
  final ProxyCardType? card;
  final ThemeStyle? board;
  final bool? floatingNavigationBar;
  final TabAnimation? tabAnimation;
  final LiquidGlassMode? liquidGlass;
  final int? color;
  final ColorStyle? colorStyle;
  final bool? pureBlack;

  static const proxiesPrefix = 'proxies.';
  static const appPrefix = 'app.';

  static const boardNames = {
    'extended': ThemeStyle.enhanced,
    'standard': ThemeStyle.original,
  };

  static final _hex = RegExp(r'^[0-9A-F]{6}([0-9A-F]{2})?$');

  static int? colorOf(String value) {
    final hex = value.replaceFirst('#', '').toUpperCase();
    if (!_hex.hasMatch(hex)) {
      return null;
    }
    return int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  }

  static bool? _boolOf(String value) => switch (value) {
    'true' || 'yes' || '1' => true,
    'false' || 'no' || '0' => false,
    _ => null,
  };

  static ViewRequest? parse(String? raw) {
    if (raw == null) {
      return null;
    }
    ProxiesType? type;
    ProxiesSortType? sort;
    ProxiesLayout? layout;
    ProxiesIconStyle? icon;
    ProxyCardType? card;
    ThemeStyle? board;
    bool? floatingNavigationBar;
    TabAnimation? tabAnimation;
    LiquidGlassMode? liquidGlass;
    int? color;
    ColorStyle? colorStyle;
    bool? pureBlack;
    T? named<T extends Enum>(List<T> values, String value) =>
        values.firstWhereOrNull((item) => item.name == value);
    for (final entry in raw.split(';')) {
      final colon = entry.indexOf(':');
      if (colon == -1) {
        continue;
      }
      final key = entry.substring(0, colon).trim().toLowerCase();
      final value = entry.substring(colon + 1).trim().toLowerCase();
      final app = key.startsWith(appPrefix);
      if (!app && !key.startsWith(proxiesPrefix)) {
        continue;
      }
      final name = key.substring(app ? appPrefix.length : proxiesPrefix.length);
      switch ((app, name)) {
        case (false, 'type'):
          type = named(ProxiesType.values, value) ?? type;
        case (false, 'sort'):
          sort = named(ProxiesSortType.values, value) ?? sort;
        case (false, 'layout'):
          layout = named(ProxiesLayout.values, value) ?? layout;
        case (false, 'icon'):
          icon = named(ProxiesIconStyle.values, value) ?? icon;
        case (false, 'card'):
          card = named(ProxyCardType.values, value) ?? card;
        case (true, 'board'):
          board = boardNames[value] ?? board;
        case (true, 'navbar'):
          floatingNavigationBar = switch (value) {
            'floating' => true,
            'docked' => false,
            _ => floatingNavigationBar,
          };
        case (true, 'tabs'):
          tabAnimation = named(TabAnimation.values, value) ?? tabAnimation;
        case (true, 'glass'):
          liquidGlass = named(LiquidGlassMode.values, value) ?? liquidGlass;
        case (true, 'color'):
          color = colorOf(value) ?? color;
        case (true, 'style'):
          colorStyle = named(ColorStyle.values, value) ?? colorStyle;
        case (true, 'black'):
          pureBlack = _boolOf(value) ?? pureBlack;
      }
    }
    final view = ViewRequest(
      type: type,
      sort: sort,
      layout: layout,
      icon: icon,
      card: card,
      board: board,
      floatingNavigationBar: floatingNavigationBar,
      tabAnimation: tabAnimation,
      liquidGlass: liquidGlass,
      color: color,
      colorStyle: colorStyle,
      pureBlack: pureBlack,
    );
    return view.isEmpty ? null : view;
  }

  List<Object?> get _fields => [
    type,
    sort,
    layout,
    icon,
    card,
    board,
    floatingNavigationBar,
    tabAnimation,
    liquidGlass,
    color,
    colorStyle,
    pureBlack,
  ];

  bool get isEmpty => _fields.every((field) => field == null);

  bool get touchesTheme =>
      board != null ||
      liquidGlass != null ||
      color != null ||
      colorStyle != null ||
      pureBlack != null;

  bool get touchesApp => floatingNavigationBar != null || tabAnimation != null;

  @override
  bool operator ==(Object other) =>
      other is ViewRequest &&
      const ListEquality<Object?>().equals(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);
}

/// `<url>[,<visibility 1-100>]`: a picture behind every page and how much
/// of it to let through.
class PanelBackground {
  const PanelBackground({required this.url, this.visibility});

  final String url;
  final int? visibility;

  static PanelBackground? parse(String? raw) {
    if (raw == null) {
      return null;
    }
    final comma = raw.lastIndexOf(',');
    final url = (comma == -1 ? raw : raw.substring(0, comma)).trim();
    final visibility = comma == -1
        ? null
        : int.tryParse(raw.substring(comma + 1).trim());
    if (!url.isUrl) {
      return null;
    }
    return PanelBackground(url: url, visibility: visibility?.clamp(1, 100));
  }

  @override
  bool operator ==(Object other) =>
      other is PanelBackground &&
      other.url == url &&
      other.visibility == visibility;

  @override
  int get hashCode => Object.hash(url, visibility);
}

/// A link with the number after the comma that says when to show it.
class LinkOffer {
  const LinkOffer({required this.url, this.threshold});

  final String url;
  final double? threshold;

  static LinkOffer? parse(String? raw) {
    if (raw == null) {
      return null;
    }
    final comma = raw.lastIndexOf(',');
    final url = (comma == -1 ? raw : raw.substring(0, comma)).trim();
    if (!url.isUrl) {
      return null;
    }
    final threshold = comma == -1
        ? null
        : double.tryParse(raw.substring(comma + 1).trim());
    return LinkOffer(url: url, threshold: threshold);
  }

  @override
  bool operator ==(Object other) =>
      other is LinkOffer && other.url == url && other.threshold == threshold;

  @override
  int get hashCode => Object.hash(url, threshold);
}

enum ProfileOfferKind { buyPlan, buyTraffic }

class ProfileOffer {
  const ProfileOffer({required this.kind, required this.url});

  final ProfileOfferKind kind;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is ProfileOffer && other.kind == kind && other.url == url;

  @override
  int get hashCode => Object.hash(kind, url);
}

/// The offers [profile]'s plan has reached, renewal first.
List<ProfileOffer> visibleOffersOf(Profile? profile, {DateTime? now}) {
  if (profile == null) {
    return const [];
  }
  final headers = profile.headers;
  final info = profile.subscriptionInfo;
  final offers = <ProfileOffer>[];
  final plan = headers.buyPlan;
  if (plan != null) {
    final threshold = plan.threshold;
    final expire = info?.expire ?? 0;
    final show = threshold == null
        ? true
        : expire > 0 &&
              DateTime.fromMillisecondsSinceEpoch(
                    expire * 1000,
                  ).difference(now ?? DateTime.now()).inDays <=
                  threshold;
    if (show) {
      offers.add(ProfileOffer(kind: ProfileOfferKind.buyPlan, url: plan.url));
    }
  }
  final traffic = headers.buyTraffic;
  if (traffic != null) {
    final threshold = traffic.threshold;
    final total = info?.total ?? 0;
    final show = threshold == null
        ? true
        : total > 0 &&
              math.max(0, total - (info!.upload + info.download)) /
                      total *
                      100 <=
                  threshold;
    if (show) {
      offers.add(
        ProfileOffer(kind: ProfileOfferKind.buyTraffic, url: traffic.url),
      );
    }
  }
  return offers;
}

extension ProfileHeaders on Profile {
  ProviderHeaders get headers => ProviderHeaders(providerHeaders);

  String? get announcement => headers.announcement;
}
