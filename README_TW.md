<div>

**README Languages**

[**🇺🇸 English**](README.md)  
[**🇷🇺 Русский**](README_RU.md)  
[**🇨🇳 简体中文**](README_ZH.md)  
[**🇯🇵 日本語**](README_JP.md)  

</div>

## FlClashX

[![下載量](https://img.shields.io/github/downloads/pluralplay/FlClashX/total?style=flat-square&logo=github)](https://github.com/pluralplay/FlClashX/releases/)
[![最新版本](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![授權條款](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![頻道](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClash)

基於 ClashMeta 的多代理平台客戶端 [FlClash](https://github.com/chen08209/FlClash) 的一個子分支，簡單易用且開源無廣告。

在桌面端：
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

在行動端：
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## 修改的功能：

🛠️ 修復預設設定：啟用程序搜尋模式、啟用 TUN 模式、關閉系統代理模式、將代理列表顯示模式設定為「列表」、更改新增訂閱時的相機行為。

🇷🇺 為安裝程式加入俄語，並重新設計應用程式內的本地化。

✈️ 將 HWID 傳輸至面板（僅適用於 <a href="">Remnawave</a>）。

💻 新增「公告」小工具，將面板的公告傳輸至小工具（僅適用於 <a href="">Remnawave</a>）。

📺 優化 Android TV 的控制項。

+ 在選單中加入「貼上」按鈕，以透過連結新增訂閱。

+ 加入設定檔選擇按鈕。

+ 加入透過 QR Code 從行動應用程式傳輸設定檔的功能。

🪪 重新設計設定檔卡片：

+ 使用帶有變色流量條的流量金額（若流量無限則不顯示）。

+ 訂閱到期日期（若年份為 2099，則顯示「永久訂閱」）。

+ 在設定檔中加入新的「支援」按鈕，該按鈕從面板提取 `supportUrl`。

+ 設定檔的自動更新間隔現在可正確從面板傳輸。

🌐 加入從訂閱頁面解析自訂標頭：

+ `flclashx-widgets`：依照從訂閱接收的順序排列小工具。

| 值  | 小工具名稱 |
| :---: | ------------- |
| `announce`  | 公告 Logo |
| `networkSpeed`  | 網路速度 |
| `outboundModeV2`  | 代理模式（新類型） |
| `outboundMode`  | 代理模式（舊類型） |
| `trafficUsage`  | 流量使用情況 |
| `networkDetection`  | 偵測位置與 IP |
| `tunButton`  | TUN 按鈕（僅限桌面端） |
| `vpnButton`  | VPN 按鈕（僅限 Android） |
| `systemProxyButton`  | 系統代理按鈕（僅限桌面端） |
| `intranetIp`  | 內網 IP 位址 |
| `memoryInfo`  | 記憶體使用情況 |
| `metainfo`  | 設定檔資訊 |

使用方式：
```bash
flclashx-widgets: announce,metainfo,outboundModeV2,networkDetection
```

+ `flclashx-view`：設定從訂閱取得的代理頁面的外觀。

| 值  | 說明 | 可能的值 |
| :---: | ------------- | ------------- |
| `type`  | 顯示模式 | `list`,`tab` |
| `sort`  | 排序類型 | `none`,`delay`,`name` |
| `layout`  | 版面配置 | `loose`,`standard`,`tight` |
| `icon`  | 圖示樣式（用於列表顯示） | `none`,`standard`,`icon` |
| `card`  | 卡片大小 | `expand`,`shrink`,`min` |

使用方式：
```bash
flclashx-view: type:list; sort:delay; layout:tight; icon:standard; card:shrink
```

+ `flclashx-custom`：控制 Dashboard 與 ProxyView 樣式的套用。

| 值  | 說明 |
| :---: | ------------- |
| `add`  | 樣式僅在首次新增訂閱時套用 |
| `update`  | 每次更新訂閱時皆套用樣式 |

使用方式：
```bash
flclashx-custom: update
```

+ `flclashx-denywidgets`：設定為 `true` 時，禁用編輯 Dashboard 頁面。接受 `true/false`。

使用方式：
```bash
flclashx-denywidgets: true
```

## 應用程式使用

### Linux
⚠️ 使用前，請確保已安裝以下相依套件：
```bash
sudo apt-get install libayatana-appindicator3-dev
sudo apt-get install libkeybinder-3.0-dev
```

### Android
支援以下操作：
```bash
com.follow.clashx.action.START

com.follow.clashx.action.STOP

com.follow.clashx.action.CHANGE
```

## 下載
<a href=""><img alt="在 GitHub 上取得" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## 支援開發
<p style="text-align: center;">
如果您喜歡此專案，可在右上角為開發者送上一顆小星星 (⭐)。<br>
若您想以小額贊助支援開發，請<a href="">點此</a>。
</p>

**TON USDT:** `UQDSfrJ_k1BdsknhdR_zj4T3Is3OdMylD8PnDJ9mxO35i-TE`

## 譯者

Chinese Translation/中文譯者: [Heliumray](https://github.com/heliumray)
