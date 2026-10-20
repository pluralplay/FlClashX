# Заголовки подписки

FlClashX читает HTTP-заголовки ответа, которым панель отдаёт подписку, и хранит их
на профиле. Заголовки перечитываются при каждом обновлении подписки, а те, что
меняют настройки приложения, применяются заново при каждом обновлении активного
профиля и при переключении на него. Что заголовок не называет, остаётся как
выставил пользователь. Имена заголовков регистронезависимы.

## Что приложение отправляет

Каждая загрузка подписки идёт с `User-Agent: FlClashX/v<версия> core/v<mihomo> Platform/<ос>`,
например `FlClashX/v0.5.0 core/v1.19.32 Platform/android`.

Если у профиля включено «Отправлять HWID» (по умолчанию включено, переключатель
есть при добавлении по ссылке и в редактировании подписки), добавляются:

| Заголовок | Значение |
|---|---|
| `x-hwid` | Android: `ANDROID_ID`; десктоп: 16 верхних hex-символов SHA-256 от MachineGuid (Windows), systemGUID (macOS), machine-id (Linux) |
| `x-device-os` | `Android`, `Windows`, `macOS`, `Linux` |
| `x-ver-os` | версия ОС |
| `x-device-model` | модель устройства |

Заголовки уходят и на основной адрес, и на запасные из `flclashx-newdomain`.

## Общие заголовки

| Заголовок | Формат | Что делает |
|---|---|---|
| `subscription-userinfo` | `upload=<байт>; download=<байт>; total=<байт>; expire=<unix-секунды>` | Трафик и срок подписки на карточке профиля и дашборде; `expire` питает уведомления об окончании. Поля можно опускать, `total=0` означает безлимит, `expire=0` бессрочно |
| `content-disposition` | `attachment; filename="имя.yaml"` | Имя профиля при добавлении по ссылке, если нет `profile-title` |
| `announce` | текст, либо base64, либо `base64:<base64>` | Карточка объявления на дашборде (до 200 символов) и текст диалога про лимит устройств |
| `support-url` | URL | Кнопка «Поддержка» на карточке профиля и в диалоге про лимит устройств |
| `profile-title` | текст, либо base64, либо `base64:<base64>` | Имя профиля при добавлении по ссылке. Без него берётся имя файла из `content-disposition`. Имя, которое пользователь задал сам, не трогается |
| `profile-web-page-url` | URL | Кнопка «Сайт» с глобусом на карточке профиля, рядом с «Поддержка» и «Обновить» |
| `profile-update-interval` | целое число часов, больше 0 | Задаёт интервал автообновления профиля |
| `x-hwid-max-devices-reached` | `true` | Диалог с текстом `announce` и кнопкой «Поддержка»; всегда при ручном обновлении или добавлении, при автообновлении только когда флаг появился |
| `x-hwid-not-supported` | `true` | Диалог «HWID не поддерживается» с кнопкой «Поддержка»: если у профиля отправка HWID выключена, говорит, что приложение его не отправило, и предлагает включить; иначе что платформа не может его дать. `announce` сюда не подставляется |

## Заголовки `flclashx-*`

Краткая выжимка только по ним: [flclashx-headers.md](flclashx-headers.md).

| Заголовок | Формат | Что делает |
|---|---|---|
| `flclashx-newdomain` | до пяти через запятую: `host`, `host:port` или `https://host` | Запасные адреса панели. Пробуются по порядку, когда основной не отвечает. После «жёсткого» отказа (домен не резолвится, 404, 410) профиль переезжает на ответивший адрес насовсем |
| `flclashx-servicename` | текст или base64 | Название сервиса в шапке расширенного дашборда |
| `flclashx-servicelogo` | URL картинки, можно base64 от URL, SVG поддерживается | Логотип в шапке расширенного дашборда |
| `flclashx-serverinfo` | имя группы прокси, текст или base64 | Группа, чей выбранный сервер показывается на расширенном дашборде |
| `flclashx-buyplan` | `URL` или `URL,<дней>` | Кнопка «Продлить подписку». С числом появляется, когда до конца подписки осталось не больше указанных дней |
| `flclashx-buytraffic` | `URL` или `URL,<процентов>` | Кнопка докупки трафика. С числом появляется, когда осталось не больше указанного процента трафика |
| `flclashx-widgets` | имена карточек через запятую | Набор и порядок карточек обычного дашборда. На расширенный дашборд и десктопную раскладку не влияет |
| `flclashx-background` | `URL` или `URL,<видимость 1–100>` | Картинка под всеми полноэкранными страницами, приглушённая цветом страницы. Без числа видно 8 %. Качается один раз в дисковый кэш |
| `flclashx-view` | `ключ:значение;...` | Внешний вид, см. ниже |
| `flclashx-settings` | флаги через запятую: `minimize`, `autorun`, `shadowstart`, `autostart`, `autoupdate`, `openlogs`, `closeconnections` | Названные переключатели приложения включаются, остальные из списка выключаются |
| `flclashx-special` | флаги через запятую: `androidsecure`, `noglobal`, `denywidgets` | Особые режимы. `androidsecure` на Android обнуляет локальные порты, прячет пункт «Порт» и выключает системный прокси VPN; подписки и ресурсы приложение тогда качает напрямую, а не через локальный порт. На других платформах ничего не делает. `noglobal` убирает режим Global: из карточки и панели выбора режима, кнопки «Правила/Глобальный», из трея целиком уходит выбор режима, горячая клавиша не срабатывает, а выбранный Global переводится в Rule. `denywidgets` прячет кнопку «Редактировать дашборд» |

### Карточки для `flclashx-widgets`

`currentOutbound`, `announcement`, `networkSpeed`, `outboundMode`, `vpnButton`
(только Android), `networkTakeover` (только десктоп), `serviceStatus`,
`profiles`, `proxyGroups`, `connectionStats`, `intranetIp`, `memoryInfo`.

Карточка статуса показывается всегда, объявление появляется само, пока панель
шлёт `announce`. Регистр имён не важен.

Если ни одно имя не распознано, настройка пользователя не трогается.

### Ключи `flclashx-view`

Одна строка `ключ:значение;ключ:значение`. Пробелы вокруг игнорируются,
значения регистронезависимы. Неизвестные ключи и значения пропускаются.

Вкладка прокси, префикс `proxies.`:

| Ключ | Значения |
|---|---|
| `proxies.type` | `list`, `tab` |
| `proxies.sort` | `none`, `delay`, `name` |
| `proxies.layout` | `loose`, `standard`, `tight` |
| `proxies.icon` | `filled`, `plain`, `hidden` |
| `proxies.card` | `loose`, `standard`, `compact` |

Вид приложения, префикс `app.` обязателен:

| Ключ | Значения |
|---|---|
| `app.board` | `extended` (расширенный дашборд с логотипом, планом и сервером), `standard` |
| `app.navbar` | `floating` (плавающая нижняя панель), `docked` (закреплённая) |
| `app.tabs` | `slide` (сдвиг), `fade` (растворение) |
| `app.glass` | `none`, `standard`, `ultra` |
| `app.color` | `RRGGBB` или `AARRGGBB`, с `#` или без; цвет становится основным и добавляется в палитру |
| `app.style` | `vivid`, `tinted`, `soft`, `monochrome` |
| `app.black` | `true`, `false` (чистый чёрный фон в тёмной теме) |

## Пример ответа панели

```http
HTTP/1.1 200 OK
Content-Type: text/yaml; charset=utf-8
Content-Disposition: attachment; filename="MyVPN.yaml"
Subscription-Userinfo: upload=0; download=5368709120; total=107374182400; expire=1767225600
profile-title: base64:TXlWUE4g4oCUINCf0YDQtdC80LjRg9C8
profile-web-page-url: https://my.myvpn.example
profile-update-interval: 12
announce: base64:0J/RgNC40LLQtdGCISDQodC10YDQstC10YAg0L7QsdC90L7QstC70ZHQvSwg0L/QtdGA0LXQt9Cw0L/Rg9GB0YLQuNGC0LUg0L/RgNC40LvQvtC20LXQvdC40LUu
support-url: https://t.me/myvpn_support
flclashx-newdomain: sub2.myvpn.example, https://sub3.myvpn.example:8443
flclashx-servicename: MyVPN
flclashx-servicelogo: https://cdn.myvpn.example/logo.svg
flclashx-serverinfo: Auto
flclashx-buyplan: https://my.myvpn.example/renew,7
flclashx-buytraffic: https://my.myvpn.example/traffic,10
flclashx-widgets: currentOutbound,announcement,profiles,proxyGroups,networkSpeed
flclashx-background: https://cdn.myvpn.example/bg.jpg,25
flclashx-view: app.board:extended;app.color:#FF5733;app.style:soft;app.black:false;app.navbar:docked;app.tabs:fade;app.glass:standard;proxies.type:tab;proxies.sort:delay;proxies.card:compact
flclashx-settings: minimize,autostart,closeconnections
flclashx-special: androidsecure,noglobal,denywidgets
```

Ответ при превышении лимита устройств отдаётся вместе с конфигом-заглушкой:

```http
HTTP/1.1 200 OK
x-hwid-max-devices-reached: true
announce: base64:0JTQvtGB0YLQuNCz0L3Rg9GCINC70LjQvNC40YIg0YPRgdGC0YDQvtC50YHRgtCyLg==
support-url: https://t.me/myvpn_support
```

## Шаблон для панели

Массив `headers` из пар `key`/`value`, как его принимают настройки панели. Хост-заголовки
(`subscription-userinfo`, `profile-title`, `announce`, `support-url`) панель обычно
добавляет сама.

```json
"headers": [
  {
    "key": "flclashx-view",
    "value": "proxies.type:list;proxies.sort:none;proxies.layout:standard;app.board:extended;app.tabs:slide;app.glass:ultra;app.color:#007AFF;app.style:tinted;app.black:false;app.navbar:floating"
  },
  {
    "key": "flclashx-widgets",
    "value": "profiles,announcement,intranetIp,networkTakeover,vpnButton,currentOutbound"
  },
  {
    "key": "flclashx-background",
    "value": "https://assets.example.com/back.jpg,20"
  },
  {
    "key": "flclashx-servicename",
    "value": "Example VPN"
  },
  {
    "key": "flclashx-servicelogo",
    "value": "https://assets.example.com/logo.png"
  },
  {
    "key": "flclashx-settings",
    "value": "minimize, autorun, shadowstart, autostart, autoupdate"
  },
  {
    "key": "flclashx-serverinfo",
    "value": "SERVERS"
  },
  {
    "key": "flclashx-special",
    "value": "noglobal,androidsecure,denywidgets"
  },
  {
    "key": "flclashx-buytraffic",
    "value": "https://shop.example.com/#/buy-extra-traffic,10"
  },
  {
    "key": "flclashx-buyplan",
    "value": "https://shop.example.com/#/buy-plan,7"
  }
]
```

## Ключи конфига, которые подписка задаёт приложению

Кроме заголовков, приложение читает из YAML подписки (и локального файла
профиля) ключи ниже и записывает их в свои настройки при каждом обновлении
подписки и при переключении на профиль. Настройки показывают то, с чем реально
работает ядро. Ключ, которого в файле нет, возвращается к значению по умолчанию,
чтобы значение прошлой подписки не залипло. Пользовательские профили и профили
со скриптом не трогают настройки.

| Ключ | По умолчанию, если не назван |
|---|---|
| `mixed-port` | 7890 |
| `port`, `socks-port`, `redir-port`, `tproxy-port` | 0 |

Свои загрузки (подписки, ресурсы, проверки) приложение при работающем ядре
ведёт через `mixed-port`, без него через `port`. Если оба нулевые (или стоит
`androidsecure`), запрос идёт без локального порта: при включённом TUN/VPN он
всё равно попадает в ядро и идёт по правилам, без TUN уходит в сеть напрямую.

| `allow-lan` | false |
| `ipv6` | true |
| `log-level` | `error` |
| `find-process-mode` | `always` (`strict` считается как `always`) |
| `interface-name` | пусто |
| `routing-mark` | 0 |
| `tcp-concurrent`, `unified-delay` | true |
| `keep-alive-interval`, `keep-alive-idle`, `disable-keep-alive` | 30, 15, false |
| `external-controller` | выключен; адрес из файла (например `127.0.0.1:9091`) включает контроллер на нём |
| `secret` | пусто; контроллер без секрета открыт без пароля |
| `geodata-loader` | `memconservative` |
| `geo-auto-update`, `geo-update-interval` | false, 24 |
| `geox-url` | ссылки MetaCubeX; пустое значение ключа оставляет ссылку по умолчанию |
| `global-ua` | User-Agent приложения; ключ влияет только на загрузки самого ядра, подписки приложение всегда качает со своим User-Agent |
| `tun.device`, `tun.stack` | `FlClashX`, `mips` |

Два ключа подписка задаёт, но к значению по умолчанию не возвращает, потому что
их пользователь переключает сам: `mode`, `tun.enable`. Режим `global`
из файла игнорируется, если панель запретила его флагом `noglobal` в `flclashx-special`.

`external-ui`, `external-ui-name` и `external-ui-url` уходят в ядро как есть:
ядро отдаёт панель по адресу контроллера `/ui` и само скачивает её по ссылке,
если папка пуста. Если контроллер включён, а `external-ui` не задан, приложение
само подставляет `external-ui: ui` и ссылку на zashboard
(`dist-cdn-fonts.zip` из последнего релиза). Пункт «Zashboard» в настройках,
сразу под «Ресурсы», появляется при включённом контроллере и открывает панель в браузере
с уже подставленными адресом, портом и секретом. Путь должен быть относительным и без `..`, он считается от
рабочей папки ядра; абсолютный путь ядро отвергло бы вместе со всем конфигом,
поэтому приложение его отбрасывает. Панель доступна только пока включён сам
контроллер, то есть пока в файле есть `external-controller`.

Значение, которое приложение не понимает (порт вне диапазона, незнакомый
уровень лога), считается отсутствующим. Остальное из файла подписки
(`dns`, `sniffer`, `ntp`, `hosts`, провайдеры, `listeners`) уходит в ядро как
есть, с поправками из переопределений профиля.

## Описания в YAML подписки

| Ключ | Где | Что делает |
|---|---|---|
| `serverDescription` | у прокси в `proxies` | Подпись под узлом в списке прокси вместо типа; флаг из неё попадает на карточку сервера |
| `groupDescription` | у группы в `proxy-groups` | Подпись свёрнутой группы в списке прокси. Тип группы (Selector, URLTest, Fallback) не показывается никогда |

## Что пользователь может забрать себе

Строка настройки, которую задаёт подписка (переключатели из `flclashx-settings`,
ключи `flclashx-view` на странице темы и в настройках вкладки прокси, ключи
конфига из таблицы выше), показана приглушённой, а вверху страницы с такими
строками появляется подсказка об этом. Строка показана приглушённой и на тап спрашивает,
хочет ли пользователь менять её сам. После согласия строка принадлежит
пользователю: обновления подписки и смена профиля её больше не трогают. Правый
клик или долгое нажатие по такой строке предлагает «Вернуть провайдеру», а пункт
«Вернуть настройки провайдеру» в «Общие → Логи и диагностика» возвращает всё
разом. Режим и TUN с дашборда в этот механизм не входят: их подписка задаёт, но
никогда не сбрасывает.

## Чего больше нет

`flclashx-hex`, `flclashx-newboard`, `flclashx-custom`, `flclashx-globalmode`,
`flclashx-androidsecure` и `flclashx-denywidgets` убраны: цвет и выбор
дашборда задаются через `flclashx-view`, флаги `noglobal`, `androidsecure` и
`denywidgets` через `flclashx-special`, а настройки из заголовков применяются
всегда, без политики `add`/`update`. Старые имена карточек, старые значения
`flclashx-view` и ключи без префикса больше не понимаются.

Ещё не перенесены из старого форка: `flclashx-override` у группы GLOBAL.

## Уведомление об окончании подписки

За 3, 2, 1 день, в день окончания и после истечения приложение показывает
системное уведомление на всех платформах: заголовок из `flclashx-servicename`
или имя профиля, тап ведёт на `flclashx-buyplan`, иначе на `support-url`.
Каждый порог показывается один раз для данной даты окончания. Если система
уведомления не даёт, например пользователь запретил их на Android, то же
самое показывается диалогом внутри приложения.
