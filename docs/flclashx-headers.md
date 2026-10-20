# Заголовки `flclashx-*`

## Сводная таблица

| Заголовок | Формат | Что делает |
|---|---|---|
| `flclashx-newdomain` | до пяти через запятую: `host`, `host:port` или `https://host` | Запасные адреса панели. Пробуются по порядку, когда основной не отвечает. После жёсткого отказа (домен не резолвится, 404, 410) профиль переезжает на ответивший адрес насовсем |
| `flclashx-servicename` | текст или base64 | Название сервиса в шапке расширенного дашборда; заголовок уведомлений об окончании подписки |
| `flclashx-servicelogo` | URL картинки, можно base64 от URL, SVG поддерживается | Логотип в шапке расширенного дашборда |
| `flclashx-serverinfo` | имя группы прокси, текст или base64 | Группа, чей выбранный сервер показывается на панели сервера расширенного дашборда с флагом и IP |
| `flclashx-buyplan` | `URL` или `URL,<дней>` | Кнопка «Продлить подписку». С числом появляется, когда до конца подписки осталось не больше указанных дней. Тап по уведомлению об окончании ведёт сюда |
| `flclashx-buytraffic` | `URL` или `URL,<процентов>` | Кнопка докупки трафика. С числом появляется, когда осталось не больше указанного процента трафика |
| `flclashx-widgets` | имена карточек через запятую | Набор и порядок карточек обычного дашборда. На расширенный дашборд и десктопную раскладку не влияет |
| `flclashx-background` | `URL` или `URL,<видимость 1–100>` | Картинка под всеми полноэкранными страницами, приглушённая цветом страницы. Без числа видно 8 %. Качается один раз в дисковый кэш |
| `flclashx-view` | `ключ:значение;...` | Внешний вид приложения и вкладки прокси |
| `flclashx-settings` | флаги через запятую | Переключатели приложения |
| `flclashx-special` | флаги через запятую | Особые режимы |

Примеры ниже даны в том виде, в каком заголовки добавляются в настройках
панели: элемент массива `headers` из пары `key`/`value`.

## `flclashx-newdomain`

До пяти запасных адресов панели через запятую: `host`, `host:port` или
`https://host`. Пробуются по порядку, когда основной не отвечает. После
жёсткого отказа (домен не резолвится, 404, 410) профиль переезжает на
ответивший адрес насовсем.

```json
{ "key": "flclashx-newdomain", "value": "sub2.example.com, https://sub3.example.com:8443" }
```

## `flclashx-servicename`

Название сервиса: шапка расширенного дашборда и заголовок уведомлений об
окончании подписки. Текст или base64.

```json
{ "key": "flclashx-servicename", "value": "Example VPN" }
```

## `flclashx-servicelogo`

Логотип в шапке расширенного дашборда. URL картинки, SVG поддерживается,
можно передать base64 от URL.

```json
{ "key": "flclashx-servicelogo", "value": "https://assets.example.com/logo.png" }
```

## `flclashx-serverinfo`

Имя группы прокси, чей выбранный сервер показывается на панели сервера
расширенного дашборда с флагом и IP. Текст или base64.

```json
{ "key": "flclashx-serverinfo", "value": "SERVERS" }
```

## `flclashx-buyplan`

Кнопка «Продлить подписку». `URL` или `URL,<дней>`: с числом кнопка появляется,
когда до конца подписки осталось не больше указанных дней. Тап по уведомлению
об окончании подписки ведёт сюда.

```json
{ "key": "flclashx-buyplan", "value": "https://shop.example.com/#/buy-plan,7" }
```

## `flclashx-buytraffic`

Кнопка докупки трафика. `URL` или `URL,<процентов>`: с числом кнопка
появляется, когда осталось не больше указанного процента трафика.

```json
{ "key": "flclashx-buytraffic", "value": "https://shop.example.com/#/buy-extra-traffic,10" }
```

## `flclashx-widgets`

Набор и порядок карточек обычного дашборда. На расширенный дашборд и
десктопную раскладку не влияет. Регистр имён не важен. Карточка статуса
показывается всегда, объявление появляется само, пока панель шлёт `announce`.
Если ни одно имя не распознано, настройка пользователя не трогается.

| Карточка | Что показывает |
|---|---|
| `currentOutbound` | Текущий сервер и кнопка смены |
| `announcement` | Объявление из `announce` |
| `networkSpeed` | Скорость сети |
| `outboundMode` | Режим работы: правила, глобальный, прямой |
| `vpnButton` | Кнопка VPN (только Android) |
| `networkTakeover` | TUN и системный прокси (только десктоп) |
| `serviceStatus` | Состояние ядра |
| `profiles` | Профиль: трафик, срок, имя сервиса |
| `proxyGroups` | Группы прокси |
| `connectionStats` | Статистика соединений |
| `intranetIp` | Локальный IP |
| `memoryInfo` | Память ядра |

```json
{ "key": "flclashx-widgets", "value": "profiles,announcement,intranetIp,networkTakeover,vpnButton,currentOutbound" }
```

## `flclashx-background`

Картинка под всеми полноэкранными страницами, приглушённая цветом страницы.
`URL` или `URL,<видимость 1–100>`, без числа видно 8 %. Качается один раз в
дисковый кэш.

```json
{ "key": "flclashx-background", "value": "https://assets.example.com/back.jpg,20" }
```

## `flclashx-view`

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

Вид приложения, префикс `app.`:

| Ключ | Значения |
|---|---|
| `app.board` | `extended` (расширенный дашборд с логотипом, планом и сервером), `standard` |
| `app.navbar` | `floating` (плавающая нижняя панель), `docked` (закреплённая) |
| `app.tabs` | `slide` (сдвиг), `fade` (растворение) |
| `app.glass` | `none`, `standard`, `ultra` |
| `app.color` | `RRGGBB` или `AARRGGBB`, с `#` или без; цвет становится основным и добавляется в палитру |
| `app.style` | `vivid`, `tinted`, `soft`, `monochrome` |
| `app.black` | `true`, `false` (чистый чёрный фон в тёмной теме) |

```json
{ "key": "flclashx-view", "value": "proxies.type:list;proxies.sort:none;proxies.layout:standard;app.board:extended;app.tabs:slide;app.glass:ultra;app.color:#007AFF;app.style:tinted;app.black:false;app.navbar:floating" }
```

## `flclashx-settings`

Названные переключатели включаются, остальные из списка выключаются.

| Флаг | Настройка |
|---|---|
| `minimize` | Сворачивать при закрытии окна |
| `autorun` | Запускать вместе с системой |
| `shadowstart` | Тихий запуск, без показа окна |
| `autostart` | Подключаться сразу после запуска приложения |
| `autoupdate` | Проверять обновления приложения |
| `openlogs` | Сбор логов |
| `closeconnections` | Закрывать соединения при смене прокси |

```json
{ "key": "flclashx-settings", "value": "minimize, autorun, shadowstart, autostart, autoupdate" }
```

## `flclashx-special`

| Флаг | Что делает |
|---|---|
| `androidsecure` | На Android обнуляет локальные порты, прячет пункт «Порт» и выключает системный прокси VPN; подписки качаются напрямую, без локального порта. На других платформах ничего не делает |
| `noglobal` | Убирает режим Global: из карточки и панели выбора режима, кнопки «Правила/Глобальный», меню трея и горячей клавиши. Выбранный Global переводится в Rule |
| `denywidgets` | Прячет кнопку «Редактировать дашборд» |

```json
{ "key": "flclashx-special", "value": "noglobal,androidsecure,denywidgets" }
```

## Что пользователь может забрать себе

Строка настройки, которую задаёт подписка (переключатели из `flclashx-settings`,
ключи `flclashx-view` на странице темы и в настройках вкладки прокси), показана
приглушённой, а вверху страницы появляется подсказка. Тап по строке спрашивает,
хочет ли пользователь менять её сам. После согласия обновления подписки и смена
профиля строку больше не трогают. Правый клик или долгое нажатие предлагает
«Вернуть провайдеру», пункт «Вернуть настройки провайдеру» в «Общие → Логи и
диагностика» возвращает всё разом.

## Чего больше нет

`flclashx-hex`, `flclashx-newboard`, `flclashx-custom`, `flclashx-globalmode`,
`flclashx-androidsecure` и `flclashx-denywidgets` убраны: цвет и выбор дашборда
задаются через `flclashx-view`, флаги `noglobal`, `androidsecure` и
`denywidgets` через `flclashx-special`, а настройки из заголовков применяются
всегда, без политики `add`/`update`. Старые имена карточек, старые значения
`flclashx-view` и ключи без префикса больше не понимаются.

## Полный шаблон для панели

```json
"headers": [
  { "key": "flclashx-view", "value": "proxies.type:list;proxies.sort:none;proxies.layout:standard;app.board:extended;app.tabs:slide;app.glass:ultra;app.color:#007AFF;app.style:tinted;app.black:false;app.navbar:floating" },
  { "key": "flclashx-widgets", "value": "profiles,announcement,intranetIp,networkTakeover,vpnButton,currentOutbound" },
  { "key": "flclashx-background", "value": "https://assets.example.com/back.jpg,20" },
  { "key": "flclashx-servicename", "value": "Example VPN" },
  { "key": "flclashx-servicelogo", "value": "https://assets.example.com/logo.png" },
  { "key": "flclashx-settings", "value": "minimize, autorun, shadowstart, autostart, autoupdate" },
  { "key": "flclashx-serverinfo", "value": "SERVERS" },
  { "key": "flclashx-special", "value": "noglobal,androidsecure,denywidgets" },
  { "key": "flclashx-buytraffic", "value": "https://shop.example.com/#/buy-extra-traffic,10" },
  { "key": "flclashx-buyplan", "value": "https://shop.example.com/#/buy-plan,7" }
]
```

То же в виде HTTP-заголовков:

```http
flclashx-view: proxies.type:list;proxies.sort:none;proxies.layout:standard;app.board:extended;app.tabs:slide;app.glass:ultra;app.color:#007AFF;app.style:tinted;app.black:false;app.navbar:floating
flclashx-widgets: profiles,announcement,intranetIp,networkTakeover,vpnButton,currentOutbound
flclashx-background: https://assets.example.com/back.jpg,20
flclashx-servicename: Example VPN
flclashx-servicelogo: https://assets.example.com/logo.png
flclashx-settings: minimize, autorun, shadowstart, autostart, autoupdate
flclashx-serverinfo: SERVERS
flclashx-special: noglobal,androidsecure,denywidgets
flclashx-buytraffic: https://shop.example.com/#/buy-extra-traffic,10
flclashx-buyplan: https://shop.example.com/#/buy-plan,7
```
