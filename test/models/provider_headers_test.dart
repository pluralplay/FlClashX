import 'dart:convert';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/color.dart';
import 'package:test/test.dart';

const _gib = 1024 * 1024 * 1024;

Profile _profile({
  Map<String, String> headers = const {},
  SubscriptionInfo? info,
}) => Profile(
  id: 1,
  autoUpdateDuration: Duration.zero,
  providerHeaders: headers,
  subscriptionInfo: info,
);

void main() {
  group('LinkOffer.parse', () {
    test('reads the link alone, or with its threshold after a comma', () {
      expect(
        LinkOffer.parse('https://pay.example.com/plan'),
        const LinkOffer(url: 'https://pay.example.com/plan'),
      );
      expect(
        LinkOffer.parse(' https://pay.example.com/plan , 3 '),
        const LinkOffer(url: 'https://pay.example.com/plan', threshold: 3),
      );
      expect(
        LinkOffer.parse('https://pay.example.com/q?a=1,b,10'),
        const LinkOffer(url: 'https://pay.example.com/q?a=1,b', threshold: 10),
      );
    });

    test('ignores what is not a link and a threshold that is not a number', () {
      expect(LinkOffer.parse(null), isNull);
      expect(LinkOffer.parse('pay now'), isNull);
      expect(
        LinkOffer.parse('https://pay.example.com,soon'),
        const LinkOffer(url: 'https://pay.example.com'),
      );
    });
  });

  group('service headers', () {
    test('read the name, logo and server group plain or base64', () {
      final encoded = base64.encode(utf8.encode('Мой VPN'));
      final headers = ProviderHeaders({
        'flclashx-servicename': encoded,
        'flclashx-servicelogo': 'https://cdn.example.com/logo.svg',
        'flclashx-serverinfo': 'Auto',
      });
      expect(headers.serviceName, 'Мой VPN');
      expect(headers.serviceLogo, 'https://cdn.example.com/logo.svg');
      expect(headers.serverGroup, 'Auto');
      expect(
        const ProviderHeaders({
          'flclashx-servicename': 'Plain Name',
        }).serviceName,
        'Plain Name',
      );
      expect(
        const ProviderHeaders({'flclashx-servicelogo': 'logo.png'}).serviceLogo,
        isNull,
      );
      expect(const ProviderHeaders({}).serviceName, isNull);
    });

    test('the board key picks the extended or the standard page', () {
      ThemeStyle? board(String? value) =>
          ProviderHeaders({'flclashx-view': ?value}).view?.board;
      expect(board('app.board:extended'), ThemeStyle.enhanced);
      expect(board('type:tab;app.board:Standard'), ThemeStyle.original);
      expect(board('app.board:fancy'), isNull);
      expect(board(null), isNull);
    });
  });

  group('device headers in the answer', () {
    test('the flags read true in any case and nothing else', () {
      expect(
        _profile(
          headers: const {'x-hwid-max-devices-reached': 'True'},
        ).headers.deviceLimitReached,
        isTrue,
      );
      expect(
        _profile(
          headers: const {'x-hwid-max-devices-reached': '1'},
        ).headers.deviceLimitReached,
        isFalse,
      );
      expect(_profile().headers.deviceLimitReached, isFalse);
      expect(
        _profile(
          headers: const {'x-hwid-not-supported': 'true'},
        ).headers.deviceIdUnsupported,
        isTrue,
      );
      expect(_profile().headers.deviceIdUnsupported, isFalse);
    });

    test('the full announcement is decoded but never cut', () {
      final long = 'x' * (maxAnnouncementLength + 5);
      final headers = _profile(
        headers: {'announce': 'base64:${base64.encode(utf8.encode(long))}'},
      ).headers;
      expect(headers.fullAnnouncement, long);
      expect(headers.announcement, hasLength(maxAnnouncementLength + 1));
      expect(_profile().headers.fullAnnouncement, isNull);
    });
  });

  group('updateInterval', () {
    test('reads whole positive hours and nothing else', () {
      ProviderHeaders of(String value) =>
          ProviderHeaders({'profile-update-interval': value});
      expect(of('12').updateInterval, const Duration(hours: 12));
      expect(of(' 1 ').updateInterval, const Duration(hours: 1));
      expect(of('0').updateInterval, isNull);
      expect(of('-3').updateInterval, isNull);
      expect(of('soon').updateInterval, isNull);
      expect(const ProviderHeaders({}).updateInterval, isNull);
    });
  });

  group('ViewRequest.parse', () {
    test('reads the proxies keys only with their prefix', () {
      expect(
        ViewRequest.parse(
          'proxies.type:tab; proxies.sort:delay ;proxies.layout:tight',
        ),
        const ViewRequest(
          type: ProxiesType.tab,
          sort: ProxiesSortType.delay,
          layout: ProxiesLayout.tight,
        ),
      );
      expect(
        ViewRequest.parse('icon:plain;proxies.card:compact'),
        const ViewRequest(card: ProxyCardType.compact),
      );
    });

    test('the older icon, card and style names mean nothing now', () {
      expect(
        ViewRequest.parse(
          'proxies.icon:standard;proxies.card:expand;app.style:tonalSpot',
        ),
        isNull,
      );
      expect(ViewRequest.parse('proxies.card:min')?.card, isNull);
    });

    test('reads the app keys only under their prefix', () {
      expect(
        ViewRequest.parse(
          'app.board:extended;app.navbar:docked;app.tabs:fade;app.glass:ultra',
        ),
        const ViewRequest(
          board: ThemeStyle.enhanced,
          floatingNavigationBar: false,
          tabAnimation: TabAnimation.fade,
          liquidGlass: LiquidGlassMode.ultra,
        ),
      );
      expect(
        ViewRequest.parse('app.board:Standard')?.board,
        ThemeStyle.original,
      );
      expect(
        ViewRequest.parse('app.navbar:floating')?.floatingNavigationBar,
        isTrue,
      );
      expect(
        ViewRequest.parse('board:extended;navbar:docked;glass:ultra'),
        isNull,
      );
      expect(
        ViewRequest.parse('app.navbar:sticky;app.tabs:zoom;app.glass:max'),
        isNull,
      );
    });

    test('reads the colour, the style and pure black', () {
      expect(
        ViewRequest.parse(
          'app.color:#ff5733;app.style:Monochrome;app.black:true',
        ),
        const ViewRequest(
          color: 0xFFFF5733,
          colorStyle: ColorStyle.monochrome,
          pureBlack: true,
        ),
      );
      expect(ViewRequest.parse('app.color:80FF5733')?.color, 0x80FF5733);
      expect(ViewRequest.parse('app.black:no')?.pureBlack, isFalse);
      expect(
        ViewRequest.parse('app.color:FF57;app.style:rainbow;app.black:maybe'),
        isNull,
      );
    });

    test('is nothing when no key is understood', () {
      expect(ViewRequest.parse('type:grid;colour:red'), isNull);
      expect(ViewRequest.parse('no colon'), isNull);
      expect(ViewRequest.parse(null), isNull);
    });
  });

  group('dashboardWidgets', () {
    test('names the cards in order, by their current names only', () {
      expect(
        const ProviderHeaders({
          'flclashx-widgets':
              ' networkSpeed, Announcement ,metainfo,outboundModeV2,profiles',
        }).dashboardWidgets,
        [
          DashboardWidget.networkSpeed,
          DashboardWidget.announcement,
          DashboardWidget.profiles,
        ],
      );
    });

    test('drops names nothing answers to and repeats', () {
      expect(
        const ProviderHeaders({
          'flclashx-widgets': 'zashboardButton,memoryInfo,memoryinfo,future',
        }).dashboardWidgets,
        [DashboardWidget.memoryInfo],
      );
      expect(
        const ProviderHeaders({
          'flclashx-widgets': 'zashboardButton',
        }).dashboardWidgets,
        isNull,
      );
      expect(const ProviderHeaders({}).dashboardWidgets, isNull);
    });

    test('editing is denied by the denywidgets special', () {
      expect(const ProviderHeaders({}).widgetEditingDenied, isFalse);
      expect(
        const ProviderHeaders({
          'flclashx-denywidgets': 'true',
        }).widgetEditingDenied,
        isFalse,
      );
      expect(
        const ProviderHeaders({
          'flclashx-special': 'noglobal, DenyWidgets',
        }).widgetEditingDenied,
        isTrue,
      );
    });
  });

  group('PanelBackground.parse', () {
    test('reads the url alone or with how much of it to show', () {
      expect(
        PanelBackground.parse('https://cdn.example.com/bg.jpg'),
        const PanelBackground(url: 'https://cdn.example.com/bg.jpg'),
      );
      expect(
        PanelBackground.parse(' https://cdn.example.com/bg.jpg , 35 '),
        const PanelBackground(
          url: 'https://cdn.example.com/bg.jpg',
          visibility: 35,
        ),
      );
      expect(
        PanelBackground.parse('https://cdn.example.com/bg.jpg,250')?.visibility,
        100,
      );
      expect(
        PanelBackground.parse('https://cdn.example.com/bg.jpg,0')?.visibility,
        1,
      );
    });

    test('is nothing without a url', () {
      expect(PanelBackground.parse('wallpaper,40'), isNull);
      expect(PanelBackground.parse(''), isNull);
      expect(PanelBackground.parse(null), isNull);
      expect(
        PanelBackground.parse(
          'https://cdn.example.com/bg.jpg,soon',
        )?.visibility,
        isNull,
      );
    });
  });

  group('globalModeAllowed', () {
    test('is taken away only by the noglobal special', () {
      expect(const ProviderHeaders({}).globalModeAllowed, isTrue);
      expect(
        const ProviderHeaders({
          'flclashx-special': 'androidsecure',
        }).globalModeAllowed,
        isTrue,
      );
      expect(
        const ProviderHeaders({
          'flclashx-special': 'androidsecure, NoGlobal',
        }).globalModeAllowed,
        isFalse,
      );
    });
  });

  group('fallbackUrlsOf', () {
    final url = Uri.parse('https://u:p@old.example.com/sub/abc?x=1');
    List<String> moved(String header) => ProviderHeaders({
      'flclashx-newdomain': header,
    }).fallbackUrlsOf(url).map((u) => u.toString()).toList();

    test('moves the link onto each host, keeping path, query and login', () {
      expect(moved('new.example.com, backup.example.net:8443'), [
        'https://u:p@new.example.com/sub/abc?x=1',
        'https://u:p@backup.example.net:8443/sub/abc?x=1',
      ]);
    });

    test('takes the scheme and port from a full origin', () {
      expect(moved('http://plain.example.com'), [
        'http://u:p@plain.example.com/sub/abc?x=1',
      ]);
      expect(
        const ProviderHeaders({
          'flclashx-newdomain': 'new.example.com',
        }).fallbackUrlsOf(Uri.parse('https://old.example.com:8443/s')),
        [Uri.parse('https://new.example.com:8443/s')],
      );
    });

    test('leaves out the current host, repeats and what is not a host', () {
      expect(moved('old.example.com, new.example.com, new.example.com'), [
        'https://u:p@new.example.com/sub/abc?x=1',
      ]);
      expect(moved('not a host, new.example.com/path, ?q, a.example.com'), [
        'https://u:p@a.example.com/sub/abc?x=1',
      ]);
      expect(moved(''), isEmpty);
      expect(const ProviderHeaders({}).fallbackUrlsOf(url), isEmpty);
    });

    test('stops at five hosts and yields nothing for a link without one', () {
      final hosts = List.generate(7, (i) => 'h$i.example.com').join(',');
      expect(moved(hosts), hasLength(5));
      expect(
        ProviderHeaders({'flclashx-newdomain': hosts}).fallbackUrlsOf(Uri()),
        isEmpty,
      );
    });
  });

  group('visibleOffersOf', () {
    final now = DateTime(2026, 10, 19, 12);
    int expireIn(int days) =>
        now.add(Duration(days: days, hours: 1)).millisecondsSinceEpoch ~/ 1000;

    test('shows nothing without a profile or without the headers', () {
      expect(visibleOffersOf(null, now: now), isEmpty);
      expect(visibleOffersOf(_profile(), now: now), isEmpty);
    });

    test('an offer without a threshold shows whatever the plan says', () {
      final profile = _profile(
        headers: const {
          'flclashx-buyplan': 'https://pay.example.com/plan',
          'flclashx-buytraffic': 'https://pay.example.com/traffic',
        },
      );
      expect(visibleOffersOf(profile, now: now), const [
        ProfileOffer(
          kind: ProfileOfferKind.buyPlan,
          url: 'https://pay.example.com/plan',
        ),
        ProfileOffer(
          kind: ProfileOfferKind.buyTraffic,
          url: 'https://pay.example.com/traffic',
        ),
      ]);
    });

    test('the renewal waits for the days left to reach its threshold', () {
      Profile ending(int days) => _profile(
        headers: const {'flclashx-buyplan': 'https://pay.example.com/plan,3'},
        info: SubscriptionInfo(expire: expireIn(days)),
      );
      expect(visibleOffersOf(ending(10), now: now), isEmpty);
      expect(visibleOffersOf(ending(3), now: now), hasLength(1));
      expect(visibleOffersOf(ending(-2), now: now), hasLength(1));
      expect(
        visibleOffersOf(
          _profile(headers: const {'flclashx-buyplan': 'https://p.example,3'}),
          now: now,
        ),
        isEmpty,
      );
    });

    test('the top-up waits for the traffic left to reach its percent', () {
      Profile used(int gib) => _profile(
        headers: const {
          'flclashx-buytraffic': 'https://pay.example.com/traffic,10',
        },
        info: SubscriptionInfo(download: gib * _gib, total: 100 * _gib),
      );
      expect(visibleOffersOf(used(50), now: now), isEmpty);
      expect(visibleOffersOf(used(90), now: now), hasLength(1));
      expect(visibleOffersOf(used(100), now: now), hasLength(1));
      expect(
        visibleOffersOf(
          _profile(
            headers: const {'flclashx-buytraffic': 'https://p.example,10'},
          ),
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('appSwitches', () {
    test('names the switches the panel turns on, lower case and trimmed', () {
      expect(
        const ProviderHeaders({
          'flclashx-settings': ' Minimize, autostart ,,OPENLOGS',
        }).appSwitches,
        {'minimize', 'autostart', 'openlogs'},
      );
    });

    test('an absent header leaves the switches to the user', () {
      expect(const ProviderHeaders({}).appSwitches, isNull);
      expect(
        const ProviderHeaders({'flclashx-settings': ''}).appSwitches,
        isNull,
      );
    });
  });

  group('specials', () {
    test('androidsecure is one of the special flags', () {
      const headers = ProviderHeaders({'flclashx-special': 'AndroidSecure, x'});
      expect(headers.specials, {'androidsecure', 'x'});
      expect(headers.androidSecure, isTrue);
    });

    test('without the header nothing special is asked', () {
      expect(const ProviderHeaders({}).specials, isNull);
      expect(const ProviderHeaders({}).androidSecure, isFalse);
    });
  });

  group('title and web page', () {
    test('the title comes plain or base64 and the page must be a URL', () {
      expect(
        const ProviderHeaders({'profile-title': 'My VPN'}).title,
        'My VPN',
      );
      expect(
        ProviderHeaders({
          'profile-title': 'base64:${base64.encode(utf8.encode('Мой VPN'))}',
        }).title,
        'Мой VPN',
      );
      expect(
        const ProviderHeaders({
          'profile-web-page-url': 'https://my.example/',
        }).webPageUrl,
        'https://my.example/',
      );
      expect(
        const ProviderHeaders({'profile-web-page-url': 'nope'}).webPageUrl,
        isNull,
      );
    });
  });
}
