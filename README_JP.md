<div>

**README Languages**

[**🇺🇸 English**](README_EN.md)  
[**🇷🇺 Русский**](README_RU.md)  
[**🇨🇳 简体中文**](README_ZH.md)  
[**🇹🇼 繁体中文**](README_TW.md)  

</div>

## FlClashX

[![ダウンロード数](https://img.shields.io/github/downloads/pluralplay/FlClashX/total?style=flat-square&logo=github)](https://github.com/pluralplay/FlClashX/releases/)
[![最新バージョン](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![ライセンス](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![Telegram チャット](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClash)

ClashMeta をベースにしたマルチプロキシクライアント **FlClash**（https://github.com/chen08209/FlClash）のサブブランチです。シンプルで使いやすく、広告なし・オープンソースです。

### デスクトップ版
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

### モバイル版
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## 変更点

🛠️ デフォルト設定を修正：プロセス検索モード有効、TUN モード有効、システムプロキシモード無効、プロキシリスト表示モードを「リスト」に設定、サブスクリプション追加時のカメラ動作を変更。

🇷🇺 インストーラにロシア語を追加し、アプリ内ローカライズを再設計。

✈️ HWID をパネルへ送信（<a href="">Remnawave</a> のみ対応）。

💻 新しい「お知らせ」ウィジェットを追加。パネルのお知らせをウィジェットへ転送（<a href="">Remnawave</a> のみ対応）。

📺 Android TV のコントロールを最適化。

+ メニューに「貼り付け」ボタンを追加し、リンクからサブスクリプションを追加できるようにしました。

+ 設定ファイル選択ボタンを追加。

+ QR コードでモバイルアプリから設定ファイルを転送できる機能を追加。

🪪 設定ファイルカードを再設計：

+ 変色するトラフィックバー付きのトラフィック量を表示（無制限の場合は非表示）。

+ サブスクリプション有効期限を表示（年が 2099 の場合は「永久サブスクリプション」）。

+ 設定ファイルに新しい「サポート」ボタンを追加し、パネルから `supportUrl` を取得。

+ 設定ファイルの自動更新間隔が正しくパネルから取得できるように。

🌐 サブスクリプションページからカスタムヘッダーを解析できるように：

+ `flclashx-widgets`：サブスクリプションから受け取った順序でウィジェットを配置。

| 値 | ウィジェット名 |
| :---: | ------------- |
| `announce` | お知らせロゴ |
| `networkSpeed` | ネットワーク速度 |
| `outboundModeV2` | プロキシモード（新タイプ） |
| `outboundMode` | プロキシモード（旧タイプ） |
| `trafficUsage` | トラフィック使用量 |
| `networkDetection` | 検出位置と IP |
| `tunButton` | TUN ボタン（デスクトップのみ） |
| `vpnButton` | VPN ボタン（Android のみ） |
| `systemProxyButton` | システムプロキシボタン（デスクトップのみ） |
| `intranetIp` | 内部 IP アドレス |
| `memoryInfo` | メモリ使用状況 |
| `metainfo` | 設定ファイル情報 |

**使用例**
```bash
flclashx-widgets: announce,metainfo,outboundModeV2,networkDetection
```

+ `flclashx-view`：サブスクリプションから取得したプロキシページの外観を制御。

| 値 | 説明 | 可能な値 |
| :---: | ------------- | ------------- |
| `type` | 表示モード | `list`,`tab` |
| `sort` | ソートタイプ | `none`,`delay`,`name` |
| `layout` | レイアウト | `loose`,`standard`,`tight` |
| `icon` | アイコンスタイル（リスト表示用） | `none`,`standard`,`icon` |
| `card` | カードサイズ | `expand`,`shrink`,`min` |

**使用例**
```bash
flclashx-view: type:list; sort:delay; layout:tight; icon:standard; card:shrink
```

+ `flclashx-custom`：Dashboard と ProxyView のスタイル適用を制御。

| 値 | 説明 |
| :---: | ------------- |
| `add` | サブスクリプションを初めて追加したときだけスタイルを適用 |
| `update` | サブスクリプションを更新するたびにスタイルを適用 |

**使用例**
```bash
flclashx-custom: update
```

+ `flclashx-denywidgets`：`true` に設定すると Dashboard ページの編集を無効化。`true` / `false` を受け付けます。

**使用例**
```bash
flclashx-denywidgets: true
```

## アプリの使い方

### Linux
⚠️ 使用前に以下の依存パッケージをインストールしてください：
```bash
sudo apt-get install libayatana-appindicator3-dev
sudo apt-get install libkeybinder-3.0-dev
```

### Android
以下のインテントをサポートしています：
```bash
com.follow.clashx.action.START
com.follow.clashx.action.STOP
com.follow.clashx.action.CHANGE
```

## ダウンロード
<a href=""><img alt="GitHub から取得" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## 開発支援
<p style="text-align: center;">
このプロジェクトが気に入ったら、右上のスター (⭐) を付けてください。<br>
少額の寄付で開発を支援したい方は<a href="">こちらをクリック</a>してください。
</p>

**TON USDT:** `UQDSfrJ_k1BdsknhdR_zj4T3Is3OdMylD8PnDJ9mxO35i-TE`

## 訳者

日本語翻訳者: [Heliumray](https://github.com/heliumray)
