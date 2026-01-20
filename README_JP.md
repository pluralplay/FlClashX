<div align="center">

## **🌍 Language**
**Jump To:**  
[**🇺🇸 English**](README.md)  |
[**🇷🇺 Русский**](README_RU.md)  |
[**🇨🇳 简体中文**](README_CN.md)  |
[**🇹🇼 繁體中文**](README_TW.md)  |
[**🇯🇵 日本語**](README_JP.md)  

</div>

# FlClashX

[![ダウンロード数](https://img.shields.io/github/downloads/pluralplay/FlClashX/total?style=flat-square&logo=github)](https://github.com/pluralplay/FlClashX/releases/)
[![最新版](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![ライセンス](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![チャンネル](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClashX)

ClashMetaベースのマルチプラットフォーム・プロキシツール[FlClash](https://github.com/chen08209/FlClash)のフォーク。シンプルで使いやすく、無広告・オープンソースです。

デスクトップ版プレビュー：

<p>
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

モバイル版プレビュー：

<p>
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## 変更履歴

🛠️ **設定系統**：プロセス検索モード、TUNモード、システムプロキシモード、プロキシ一覧表示モードのデフォルトを「リスト」に変更；QRコードを使った購読追加時のカメラ挙動を調整。

📱 **Android 120 Hz ハイリフレッシュレート対応**：Androidで最大120 Hz表示に対応。

🗑️ **アプリデータクリア**：設定内に「データクリア」ボタンを追加し、profilesフォルダ内の全ての設定をワンタップで削除。テストやリセットに便利。

🇷🇺 インストーラにロシア語を追加、アプリ内ローカライズを全面刷新。

✈️ パネル向けHWID送信を追加（<a href="https://github.com/remnawave/panel">Remnawave</a>対応）。

💻「お知らせ」ウィジェットを追加し、パネルからクライアントに通知をプッシュ（<a href="https://github.com/remnawave/panel">Remnawave</a>対応）。

📺 Android TV 操作を進化：

- 「貼り付け」ボタンを追加、URL入力がより簡単に
- 「選択設定」ボタンを追加
- QRコードを使い、スマホからTVへ設定を転送可能

🪪 プロファイルカードを刷新：

- カラフルなトラフィックバーを導入（不課金プランでは非表示）
- 購読有効期限を表示（西暦2099年は「終身有効」と表示）
- プロファイルページに「サポート」ボタンを追加し、パネルのsupportUrlを自動取得
- パネルのautoupdateintervalパラメーターが正しく反映されるようになった

🪪 新ウィジェット追加：「Meta-Info」「serviceInfo」「changeServerButton」

- 「Meta-Info」：残トラフィック・有効期限・プロファイル名を表示。3日前から目立つ色で注意喚起
- 「serviceInfo」：サービス名を表示。`flclashx-servicelogo`でカスタムロゴ（svg/png）を設定可能で、クリックするとサポートURLにジャンプ
- 「changeServerButton」：ワンタップでプロキシページへ移動

🌐 購読（subscribe）カスタムヘッダーにより、以下の設定を柔軟に制御可能：

- **flclashx-widgets**：ダッシュボードに並べるウィジェットを、購読返却順で指定

  | 値                   | 対応ウィジェット                                |
  |----------------------|-----------------------------------------------|
  | `announce`           | お知らせアイコン                              |
  | `networkSpeed`       | 論理スピード                                |
  | `outboundModeV2`     | プロキシモード（新）                         |
  | `outboundMode`       | プロキシモード（旧）                         |
  | `trafficUsage`       | トラフィック使用状況                          |
  | `networkDetection`   | 現在地・IP チェック                           |
  | `tunButton`          | TUN ボタン（デスクトップ限定）                |
  | `vpnButton`          | VPN ボタン（Android）                         |
  | `systemProxyButton`  | システムプロキシボタン（デスクトップ限定）     |
  | `intranetIp`         | イントラネットIP                            |
  | `memoryInfo`         | メモリ使用状況                                |
  | `metainfo`           | プロファイル情報                             |
  | `changeServerButton` | サーバー切替ボタン                            |
  | `serviceInfo`        | サービス情報（flclashx-servicename必須）       |

**使用例：**
```bash
flclashx-widgets: announce,metainfo,outboundModeV2,networkDetection
```

- **flclashx-view**：購読返却のプロキシページ表示方法をカスタマイズ

  | キー     | 説明               | 選択肢                              |
  |----------|--------------------|----------------------------------|
  | `type`   | 表示方式           | `list`、`tab`                    |
  | `sort`   | ソート方法         | `none`、`delay`、`name`          |
  | `layout`| レイアウト         | `loose`、`standard`、`tight`     |
  | `icon`   | アイコンスタイル    | `none`、`icon`                   |
  | `card`   | カードサイズ       | `expand`、`shrink`、`min`、`oneline`|

**使用例：**
```bash
flclashx-view: type:list; sort:delay; layout:tight; icon:icon; card:shrink
```

- **flclashx-custom**：購読によりダッシュボード／プロキシビューのスタイル適用タイミングを制御

  | 値       | 説明                             |
  |----------|----------------------------------|
  | `add`    | 購読最初追加時のみ適用          |
  | `update` | 毎回購読更新時に適用              |

**使用例：**
```bash
flclashx-custom: update
```

- **flclashx-denywidgets**：true を指定するとダッシュボード編集機能を無効化

**使用例：**
```bash
flclashx-denywidgets: true
```

- **flclashx-servicename**：ServiceInfo ウィジェットに表示するサービス名をカスタム

**使用例：**
```bash
flclashx-servicename: FlClashX
```

- **flclashx-servicelogo**：ServiceInfo ウィジェット用カスタムロゴ（png/svg）。flclashx-servicename 必須

**使用例：**
```bash
flclashx-servicelogo: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/remnawave.svg
```

- **flclashx-serverinfo**：ChangeServerButton ウィジェットに表示するプロキシグループ名。グループ内の現アクティブノード（国旗・遅延・クイック切替付）を表示

**表示要素：**
  - 国旗（serverDescription・ノード名で自動判別）
  - 現アクティブノード名
  - 現遅延（緑 <600 ms、オレンジ ≥600 ms、赤タイムアウト）
  - クイックジャンプボタン

**使用例：**
```bash
flclashx-serverinfo: Proxy
```

- **flclashx-background**：クライアントにカスタム背景画像を設定（直リンク指定）

**推奨仕様：**
  - 形式：PNG、JPG または WebP
  - 解像度：デスクトップ版 ≥1920×1080、モバイル版 1080×1920
  - サイズ：2 MB以内
  - 内容：低彩度グラデ／テクスチャ、派手すぎない
  - コントラスト：文字が読めるよう配慮

**使用例：**
```bash
flclashx-background: https://example.com/background.jpg
```

- **flclashx-settings**：ヘッダーでクライアント設定を一括管理（ユーザーはローカルで「ベンダー設定を上書き」可能）。全て **OFF** がデフォルト、指定すれば **ON**

  |       パラメータ      | 説明                           | デフォルト |
  | :-------------------: | ------------------------------ | :--------: |
  |      `minimize`       | 閉じるときトレイへ格納          |  ❌ OFF    |
  |       `autorun`       | スタートアップで自動起動        |  ❌ OFF    |
  |     `shadowstart`     | 起動後そのまま背面へ             |  ❌ OFF    |
  |      `autostart`      | アプリ起動時プロキシも自動開始   |  ❌ OFF    |
  |      `autoupdate`     | アップデートを自動チェック       |  ❌ OFF    |

**クライアント上書き：** アプリ設定で「ベンダー設定を上書き」を有効にするとローカル設定を優先

**使用例：**
```bash
flclashx-settings: minimize,autorun,shadowstart,autostart,autoupdate
```

### 設定パラメーターの上書きルール

デフォルトでは、以下の購読ヘッダー設定はクライアント側ローカル設定で **上書きされません**。

- `allow-lan` - LAN 接続を許可
- `ipv6` - IPv6 有効化
- `find-process-mode` - プロセス検索モード
- `tun-stack` - TUN スタック
- `mixed-port` - HTTP/SOCKS 混合ポート

**クライアント上書き：** アプリ設定で「ベンダー設定を上書き」または「ネットワーク設定を上書き」を有効にすると、ローカル設定が優先されます。

## 補足事項

### Linux

⚠️ 以下の依存ライブラリを事前にインストールしてください：

```bash
sudo apt-get install libayatana-appindicator3-dev
sudo apt-get install libkeybinder-3.0-dev
```

### Android

ブロードキャストによる制御に対応：

```bash
com.follow.clashx.action.START
com.follow.clashx.action.STOP
com.follow.clashx.action.CHANGE
```

## ダウンロード・インストール

<a href="https://github.com/pluralplay/FlClashX/releases"><img alt="Get on GitHub" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## 開発支援

<p align="center">
右上のStarを押すのが、オープンソースプロジェクトへの最大のサポートです⭐<br>
もし少額支援いただける場合は<a href="https://t.me/tribute/app?startapp=dtyh">こちら</a>をクリックしてください。
</p>

**TON USDT ：** `UQDSfrJ_k1BdsknhdR_zj4T3Is3OdMylD8PnDJ9mxO35i-TE`
