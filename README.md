<div>

[**English**](README_EN.md)

</div>

## FlClashX

[![Downloads](https://img.shields.io/github/downloads/pluralplay/FlClashX/total?style=flat-square&logo=github)](https://github.com/pluralplay/FlClashX/releases/)
[![Last Version](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![License](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClashX)

Форк многоплатформенного прокси-клиента FlClash на основе Mihomo, простого и удобного в использовании, с открытым исходным кодом и без рекламы.

Десктопный вид:

<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

Мобильный вид:

<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Добавленный функционал

🛠️ Исправлены стандартные настройки: режим поиска процессов вкл, режим tun вкл, режим системного прокси выкл, режим отображения списка прокси list, изменена работа камеры при добавлении подписки через QR.

📱 **Поддержка 120Гц дисплеев на Android:** пока приложение на экране, дисплей работает на самой высокой частоте (90/120/144 Гц); в фоне частота возвращается системе.

🗑️ **Очистка данных приложения:** Добавлена кнопка "Очистить данные" в настройках приложения, которая удаляет все профили из папки profiles. Полезно для устранения неполадок или сброса приложения.

🇷🇺 Добавлен русский язык в установщик и переработана локаль в приложении

✈️ Передача HWID в панель (Работает только с <a href="https://github.com/remnawave/panel">Remnawave</a>)

💻 Добавлен новый виджет "Анонсы". Передаёт анонсы из панели в виджет. (Работает только с <a href="https://github.com/remnawave/panel">Remnawave</a>)

📺 Оптимизация управления на Android TV

- добавлена кнопка "Вставить" для меню добавления подписки по ссылке
- добавлена кнопка выбора профиля
- добавлена передача профиля с мобильного приложения через QR-код

💻 macOS - приложение в нативной строке состояния (status bar) вместо оконного интерфейса.

🪪 Переработана карточка профиля на странице профиля и виджет на главной:

- Используется индикатор объёма трафика с изменением цвета (не отображается, если трафик неограничен).
- Отображается дата окончания подписки (если год — 2099, выводится «Ваша подписка вечная»).
- Добавлена новая кнопка «Поддержка» в профиле, которая подтягивает supportUrl с панели.
- Параметр autoupdateinterval для профиля теперь корректно передаётся с панели.
- Добавлен виджет "MetaInfo". Передаёт параметры с подписки на виджет. Сколько трафика осталось, когда заканчивается подписка, имя профиля, и крупно отображает сколько дней до окончании подписки осталось (за 3 дня до окончания).
- Добавлен виджет "serviceInfo". Передаёт название вашего сервиса. Можно передать дополнительно хедер `flclashx-servicelogo` для кастомного лого (поддерживается ссылка svg/png), дополнительно по клику открыватеся ссылка на поддержку (supportURL)
- Добавлен виджет "changeServerButton". По клику перенаправляет на страницу прокси.

### Заголовки подписки

Приложение читает HTTP-заголовки ответа, которым панель отдаёт подписку, и хранит их на профиле. Заголовки перечитываются при каждом обновлении подписки, а те, что меняют настройки приложения, применяются заново при каждом обновлении активного профиля и при переключении на него. Что заголовок не называет, остаётся как выставил пользователь. Имена заголовков регистронезависимы. Полное описание с примерами: [docs/panel-headers.md](docs/panel-headers.md), только `flclashx-*`: [docs/flclashx-headers.md](docs/flclashx-headers.md).

<details>
<summary><strong>Что приложение отправляет</strong></summary>

Каждая загрузка подписки идёт с `User-Agent: FlClashX/v<версия> core/v<mihomo> Platform/<ос>`, например `FlClashX/v0.5.0 core/v1.19.32 Platform/android`.

Если у профиля включено «Отправлять HWID» (по умолчанию включено), добавляются:

| Заголовок | Значение |
|---|---|
| `x-hwid` | Android: `ANDROID_ID`; десктоп: 16 верхних hex-символов SHA-256 от MachineGuid (Windows), systemGUID (macOS), machine-id (Linux) |
| `x-device-os` | `Android`, `Windows`, `macOS`, `Linux` |
| `x-ver-os` | версия ОС |
| `x-device-model` | модель устройства |
</details>

<details>
<summary><strong>Общие заголовки</strong></summary>

| Заголовок | Формат | Что делает |
|---|---|---|
| `subscription-userinfo` | `upload=; download=; total=; expire=` | Трафик и срок подписки на карточке профиля и дашборде. `total=0` безлимит, `expire=0` бессрочно. `expire` питает уведомления об окончании за 3, 2, 1 день, в день окончания и после |
| `content-disposition` | `attachment; filename="имя.yaml"` | Имя профиля при добавлении по ссылке, если нет `profile-title` |
| `profile-title` | текст, base64 или `base64:<base64>` | Имя профиля при добавлении по ссылке. Имя, заданное пользователем, не трогается |
| `profile-web-page-url` | URL | Кнопка «Сайт» на карточке профиля |
| `profile-update-interval` | часы, больше 0 | Интервал автообновления профиля |
| `announce` | текст, base64 или `base64:<base64>` | Карточка объявления на дашборде (до 200 символов) и текст диалога про лимит устройств |
| `support-url` | URL | Кнопка «Поддержка» на карточке профиля и в диалоге про лимит устройств |
| `x-hwid-max-devices-reached` | `true` | Диалог с текстом `announce` и кнопкой «Поддержка» |
| `x-hwid-not-supported` | `true` | Диалог «HWID не поддерживается» с кнопкой «Поддержка»: приложение не отправило HWID, а подписка его требует (или платформа не может его дать) |
</details>

<details>
<summary><strong>flclashx-newdomain</strong></summary>

До пяти запасных адресов панели через запятую: `host`, `host:port` или `https://host`. Пробуются по порядку, когда основной не отвечает. После жёсткого отказа (домен не резолвится, 404, 410) профиль переезжает на ответивший адрес насовсем.

```http
flclashx-newdomain: sub2.myvpn.example, https://sub3.myvpn.example:8443
```
</details>

<details>
<summary><strong>flclashx-servicename, flclashx-servicelogo, flclashx-serverinfo</strong></summary>

Шапка расширенного дашборда (`app.board:extended` в `flclashx-view`):

| Заголовок | Формат | Что делает |
|---|---|---|
| `flclashx-servicename` | текст или base64 | Название сервиса в шапке; заголовок уведомлений об окончании подписки |
| `flclashx-servicelogo` | URL картинки (SVG поддерживается), можно base64 от URL | Логотип в шапке |
| `flclashx-serverinfo` | имя группы прокси, текст или base64 | Группа, чей выбранный сервер показывается на панели сервера с флагом и IP |

```http
flclashx-servicename: MyVPN
flclashx-servicelogo: https://cdn.myvpn.example/logo.svg
flclashx-serverinfo: Auto
```
</details>

<details>
<summary><strong>flclashx-buyplan, flclashx-buytraffic</strong></summary>

| Заголовок | Формат | Что делает |
|---|---|---|
| `flclashx-buyplan` | `URL` или `URL,<дней>` | Кнопка «Продлить подписку». С числом появляется, когда до конца осталось не больше указанных дней. Тап по уведомлению об окончании ведёт сюда |
| `flclashx-buytraffic` | `URL` или `URL,<процентов>` | Кнопка докупки трафика. С числом появляется, когда осталось не больше указанного процента |

```http
flclashx-buyplan: https://my.myvpn.example/renew,7
flclashx-buytraffic: https://my.myvpn.example/traffic,10
```
</details>

<details>
<summary><strong>flclashx-widgets</strong></summary>

`flclashx-widgets` задаёт набор и порядок карточек обычного дашборда. На расширенный дашборд и десктопную раскладку не влияет. Регистр имён не важен.

`currentOutbound`, `announcement`, `networkSpeed`, `outboundMode`, `vpnButton` (только Android), `networkTakeover` (только десктоп), `serviceStatus`, `profiles`, `proxyGroups`, `connectionStats`, `intranetIp`, `memoryInfo`.

Карточка статуса показывается всегда, объявление появляется само, пока панель шлёт `announce`.

```http
flclashx-widgets: currentOutbound,announcement,profiles,proxyGroups,networkSpeed
```
</details>

<details>
<summary><strong>flclashx-background</strong></summary>

`URL` или `URL,<видимость 1–100>`. Картинка под всеми полноэкранными страницами, приглушённая цветом страницы. Без числа видно 8 %. Качается один раз в дисковый кэш.

```http
flclashx-background: https://cdn.myvpn.example/bg.jpg,25
```
</details>

<details>
<summary><strong>flclashx-view</strong></summary>

Одна строка `ключ:значение;ключ:значение`. Пробелы игнорируются, значения регистронезависимы, неизвестные ключи и значения пропускаются.

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
| `app.navbar` | `floating`, `docked` |
| `app.tabs` | `slide`, `fade` |
| `app.glass` | `none`, `standard`, `ultra` |
| `app.color` | `RRGGBB` или `AARRGGBB`, с `#` или без; становится основным цветом и добавляется в палитру |
| `app.style` | `vivid`, `tinted`, `soft`, `monochrome` |
| `app.black` | `true`, `false` (чистый чёрный фон в тёмной теме) |

```http
flclashx-view: app.board:extended;app.color:#FF5733;app.style:soft;app.navbar:docked;proxies.type:tab;proxies.sort:delay;proxies.card:compact
```
</details>

<details>
<summary><strong>flclashx-settings</strong></summary>

Флаги через запятую. Названные переключатели приложения включаются, остальные из списка выключаются.

| Флаг | Настройка |
|---|---|
| `minimize` | Сворачивать при закрытии окна |
| `autorun` | Запускать вместе с системой |
| `shadowstart` | Тихий запуск, без показа окна |
| `autostart` | Подключаться сразу после запуска приложения |
| `autoupdate` | Проверять обновления приложения |
| `openlogs` | Сбор логов |
| `closeconnections` | Закрывать соединения при смене прокси |

```http
flclashx-settings: minimize,autostart,closeconnections
```
</details>

<details>
<summary><strong>flclashx-special</strong></summary>

Флаги через запятую.

| Флаг | Что делает |
|---|---|
| `androidsecure` | На Android обнуляет локальные порты, прячет пункт «Порт» и выключает системный прокси VPN; подписки качаются напрямую, без локального порта. На других платформах ничего не делает |
| `noglobal` | Убирает режим Global: из карточки и панели выбора режима, кнопки «Правила/Глобальный», меню трея и горячей клавиши. Выбранный Global переводится в Rule |
| `denywidgets` | Прячет кнопку «Редактировать дашборд» |

```http
flclashx-special: androidsecure,noglobal,denywidgets
```
</details>

<details>
<summary><strong>Пример ответа панели</strong></summary>

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
</details>

<details>
<summary><strong>Чего больше нет</strong></summary>

`flclashx-hex`, `flclashx-newboard`, `flclashx-custom`, `flclashx-globalmode`, `flclashx-androidsecure` и `flclashx-denywidgets` убраны: цвет и выбор дашборда задаются через `flclashx-view`, режим Global, защищённый Android и запрет редактирования дашборда через `flclashx-special`, а настройки из заголовков применяются всегда, без политики `add`/`update`.
</details>

### Шаблон для панели

Тот же набор в виде, который принимают настройки панели (Remnawave и подобные): массив `headers` из пар `key`/`value`. Хост-заголовки `subscription-userinfo`, `profile-title`, `announce` и `support-url` панель обычно добавляет сама.

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

### YAML-ключи в конфиге

Кроме заголовков, приложение читает из YAML подписки ключи ниже и записывает их в свои настройки при каждом обновлении подписки и при переключении на профиль. Ключ, которого в файле нет, возвращается к значению по умолчанию, чтобы значение прошлой подписки не залипло.

<details>
<summary><strong>Ключи конфига</strong></summary>

| Ключ | По умолчанию, если не назван |
|---|---|
| `mixed-port` | 7890 |
| `port`, `socks-port`, `redir-port`, `tproxy-port` | 0 |

Свои загрузки приложение ведёт через `mixed-port`, без него через `port`; если оба нулевые или стоит `androidsecure`, запрос идёт без локального порта: при включённом TUN/VPN попадает в ядро по правилам, без TUN уходит в сеть напрямую.

| `allow-lan` | false |
| `ipv6` | true |
| `log-level` | `error` |
| `find-process-mode` | `always` (`strict` считается как `always`) |
| `interface-name` | пусто |
| `routing-mark` | 0 |
| `tcp-concurrent`, `unified-delay` | true |
| `keep-alive-interval`, `keep-alive-idle`, `disable-keep-alive` | 30, 15, false |
| `external-controller` | выключен; адрес из файла включает контроллер на нём |
| `secret` | пусто; контроллер без секрета открыт без пароля |
| `external-ui`, `external-ui-name`, `external-ui-url` | при включённом контроллере подставляется zashboard; пункт «Zashboard» в настройках открывает панель с адресом и секретом |
| `geodata-loader` | `memconservative` |
| `geo-auto-update`, `geo-update-interval` | false, 24 |
| `geox-url` | ссылки MetaCubeX |
| `global-ua` | User-Agent приложения; влияет только на загрузки самого ядра |
| `tun.device`, `tun.stack` | `FlClashX`, `mips` |

`mode` и `tun.enable` подписка задаёт, но к значению по умолчанию не возвращает, потому что их пользователь переключает сам.
</details>

<details>
<summary><strong>serverDescription и groupDescription</strong></summary>

| Ключ | Где | Что делает |
|---|---|---|
| `serverDescription` | у прокси в `proxies` | Подпись под узлом в списке прокси вместо типа; флаг из неё попадает на карточку сервера |
| `groupDescription` | у группы в `proxy-groups` | Подпись свёрнутой группы в списке прокси. Тип группы не показывается никогда |

```yaml
proxy-groups:
  - name: 🌍 Основной VPN
    type: select
    groupDescription: Авто-выбор лучшей локации
    proxies:
      - 🇩🇪 Германия
proxies:
  - name: 🇩🇪 Германия
    type: vless
    serverDescription: 🇩🇪 Франкфурт, 10 Гбит/с
```
</details>

### Настройки провайдера и пользователя

Строка настройки, которую задаёт подписка (переключатели из `flclashx-settings`, ключи `flclashx-view` на странице темы и в настройках вкладки прокси, ключи конфига из таблицы выше), показана приглушённой, а вверху страницы появляется подсказка об этом. Тап по строке спрашивает, хочет ли пользователь менять её сам. После согласия строка принадлежит пользователю: обновления подписки и смена профиля её больше не трогают. Правый клик или долгое нажатие по строке предлагает «Вернуть провайдеру», а пункт «Вернуть настройки провайдеру» в «Общие → Логи и диагностика» возвращает всё разом.

## Использование

### Linux

⚠️ Перед использованием убедитесь, что установлены следующие зависимости:

```bash
 sudo apt-get install libayatana-appindicator3-dev
 sudo apt-get install libkeybinder-3.0-dev
```

### Android

Поддерживаются следующие действия:

```bash
 com.follow.clashx.action.START

 com.follow.clashx.action.STOP

 com.follow.clashx.action.CHANGE
```

## Скачать

<a href="https://github.com/pluralplay/FlClashX/releases"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## Star

<p style="text-align: center;">
Самый простой способ поддержать разработчиков — нажать на звездочку (⭐) в верхней части страницы.<br>
Если хотите поддержать копеечкой, то можно <a href="https://t.me/tribute/app?startapp=dtyh">сделать это тут.</a></p>

**TON USDT:** `UQDSfrJ_k1BdsknhdR_zj4T3Is3OdMylD8PnDJ9mxO35i-TE`
