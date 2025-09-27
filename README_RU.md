<div>

**README Languages**

[**🇺🇸 English**](README.md)  
[**🇨🇳 简体中文**](README_ZH.md)  
[**🇹🇼 繁体中文**](README_TW.md)  
[**🇯🇵 日本語**](README_JP.md)  

</div>

## FlClashX

[![Downloads](https://img.shields.io/github/downloads/pluralplay/FlClashX/total?style=flat-square&logo=github)](https://github.com/pluralplay/FlClashX/releases/)
[![Last Version](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![License](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClashX)

Форк многоплатформенного прокси-клиента [FlClash](https://github.com/chen08209/FlClash) на основе ClashMeta, простого и удобного в использовании, с открытым исходным кодом и без рекламы.

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

🇷🇺 Добавлен русский язык в установщик и переработана локаль в приложении

✈️ Передача HWID в панель (Работает только с <a href="https://github.com/remnawave/panel">Remnawave</a>)

💻 Добавлен новый виджет "Анонсы". Передаёт анонсы из панели в виджет. (Работает только с <a href="https://github.com/remnawave/panel">Remnawave</a>)

📺 Оптимизация управления на Android TV
   + добавлена кнопка "Вставить" для меню добавления подписки по ссылке
   + добавлена кнопка выбора профиля 
   + добавлена передача профиля с мобильного приложения через QR-код

🪪 Переработана карточка профиля:

+ Используется индикатор объёма трафика с изменением цвета (не отображается, если трафик неограничен).
+ Отображается дата окончания подписки (если год — 2099, выводится «Ваша подписка вечная»).
+ Добавлена новая кнопка «Поддержка» в профиле, которая подтягивает supportUrl с панели.
+ Параметр autoupdateinterval для профиля теперь корректно передаётся с панели.

🪪 Добавлен новый виджет "Мета-Инфо". Передаёт параметры с подписки на виджет. Сколько трафика осталось, когда заканчивается подписка, имя профиля, и крупно отображает сколько дней до окончании подписки осталось.

🌐 Добавлен парсинг кастомных хедеров со страницы подписки:
   + flclashx-widgets: выстраивает виджеты в порядке, полученным с подписки

| Значение  | Виджет |
| :---: | ------------- |
| `announce`  | Анонсы  |
| `networkSpeed`  | Скорость сети  |
| `outboundModeV2`  | Режим работы прокси (новый вид)  |
| `outboundMode`  | Режим работы прокси (старый вид)  |
| `trafficUsage`  | Использование трафика  |
| `networkDetection`  | Определение локации и IP  |
| `tunButton`  | Кнопка TUN (только Desktop)  |
| `vpnButton`  | Кнопка VPN (только Android)  |
| `systemProxyButton`  | Кнопка системного прокси (только Desktop)  |
| `intranetIp`  | Локальный IP-адрес  |
| `memoryInfo`  | Использование памяти  |
| `metainfo`  | Информация о подписке  |

Использование:
```bash
flclashx-widgets: announce,metainfo,outboundModeV2,networkDetection
```

   + flclashx-view: настраивает вид страницы прокси, полученным с подписки

| Значение  | Описание | Возможные значения |
| :---: | ------------- | ------------- |
| `type`  | Режим отображения  | `list`,`tab` |
| `sort`  | Тип сортировки	  | `none`,`delay`,`name`|
| `layout`  | Макет  | `loose`,`standard`,`tight` |
| `icon`  | Стиль иконок (для list-отображения)  | `none`,`standard`,`icon` |
| `card`  | Размер карточки   | `expand`,`shrink`,`min` |


Использование:
```bash
    flclashx-view: type:list; sort:delay; layout:tight; icon:standard; card:shrink
```

   + flclashx-custom: управляет состоянием применения стилей для Dashboard и ProxyView

| Значение  | Описание |
| :---: | ------------- |
| `add`  | Стили применяются только при первом добавлении подписки  |
| `update`  | Стили применяются каждый раз при обновлении подписки |

Использование:
```bash
    flclashx-custom: update
```
   + flclashx-denywidgets: при true - запрещает редактировать страницу Dashboard. Имеет значение true/false.

Использование:
```bash
    flclashx-denywidgets: true
```

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
