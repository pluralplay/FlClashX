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

[![Downloads](https://img.shields.io/github/downloads/pluralplay/FlClashX/total?style=flat-square&logo=github)](https://github.com/pluralplay/FlClashX/releases/)
[![最新版本](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![License](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClashX)

基於 ClashMeta 的跨平台代理工具 [FlClash](https://github.com/chen08209/FlClash) 分支，簡潔易用、開源無廣告。

桌機版預覽：

<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

手機版預覽：

<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## 變更紀錄

🛠️ **設定相關**：行程搜尋模式、TUN 模式、系統代理模式、代理清單顯示模式預設改為「清單」；調整掃碼新增訂閱時的相機行為。

📱 **Android 120 Hz 高更新率支援**：在 Android 上最高支援 120Hz。

🗑️ **清除 App 資料**：設定內新增「清除資料」按鈕，一鍵刪除 profiles 資料夾底下所有設定，方便測試與重設。

🇷🇺 安裝程式新增俄文，App 內本地化全面重繪。

✈️ 新增向面板傳遞 HWID（僅支援 <a href="https://github.com/remnawave/panel">Remnawave</a>）。

💻 新增「公告」小工具，可將面板公告推送至客戶端（僅支援 <a href="https://github.com/remnawave/panel">Remnawave</a>）。

📺 Android TV 操作再進化：

- 新增「貼上」按鈕，貼上連結更簡單
- 新增「選擇設定」按鈕
- 可透過 QRCode 將設定從手機傳到電視

🪪 設定檔卡片重製：

- 導入彩色流量指示條（吃到飽則隱藏）
- 顯示訂閱到期日（年份 2099 顯示「終身有效」）
- 設定檔頁新增「客服」按鈕，自動抓取面板 supportUrl
- 面板的 autoupdateinterval 參數現在可以正確下發

🪪 加入更多小工具：「Meta-Info」、「serviceInfo」、「changeServerButton」

- 「Meta-Info」：顯示剩餘流量、到期日、設定檔名稱，到期前 3 天以高亮色提示
- 「serviceInfo」：顯示服務名稱；支援 `flclashx-servicelogo` 自訂 Logo（svg/png），點擊跳轉客服連結
- 「changeServerButton」：一鍵前往代理頁面

🌐 現在可透過訂閱自訂標頭解析下列設定：

- flclashx-widgets：按訂閱回傳順序擺放小工具

  | 值                   | 對應小工具                                      |
  |----------------------|-----------------------------------------------|
  | `announce`           | 公告圖示                                       |
  | `networkSpeed`       | 邏輯速度                                       |
  | `outboundModeV2`     | 代理模式（新）                                 |
  | `outboundMode`       | 代理模式（舊）                                 |
  | `trafficUsage`       | 流量統計                                       |
  | `networkDetection`   | 位置與 IP 檢測                                 |
  | `tunButton`          | TUN 按鈕（桌機限定）                            |
  | `vpnButton`          | VPN 按鈕（Android）                             |
  | `systemProxyButton`  | 系統代理按鈕（桌機限定）                          |
  | `intranetIp`         | 區域網路 IP                                     |
  | `memoryInfo`         | 記憶體佔用                                       |
  | `metainfo`           | 設定檔資訊                                      |
  | `changeServerButton` | 切換伺服器按鈕                                  |
  | `serviceInfo`        | 服務資訊（需加 flclashx-servicename）           |

**用法範例：**

```bash
flclashx-widgets: announce,metainfo,outboundModeV2,networkDetection
```

- flclashx-view：自訂訂閱回傳的代理頁呈現方式

| 鍵       | 說明          | 可選值                            |
|----------|---------------|----------------------------------|
| `type`   | 呈現方式      | `list`、`tab`                    |
| `sort`   | 排序方式      | `none`、`delay`、`name`          |
| `layout`| 版面配置      | `loose`、`standard`、`tight`     |
| `icon`   | 清單圖示風格   | `none`、`icon`                   |
| `card`   | 卡片尺寸      | `expand`、`shrink`、`min`、`oneline`|

**用法範例：**

```bash
flclashx-view: type:list; sort:delay; layout:tight; icon:icon; card:shrink
```

- flclashx-custom：控制 Dashboard 與 ProxyView 樣式是否套用

| 值     | 說明                         |
|--------|------------------------------|
| `add`  | 僅首次加入訂閱時套用樣式     |
| `update`| 每次更新訂閱都套用樣式       |

**用法範例：**

```bash
flclashx-custom: update
```

- flclashx-denywidgets：設為 true 時，關閉 Dashboard 編輯功能

**用法範例：**

```bash
flclashx-denywidgets: true
```

- flclashx-servicename：自訂 ServiceInfo 小工具顯示的服務名稱

**用法範例：**

```bash
flclashx-servicename: FlClashX
```

- flclashx-servicelogo：ServiceInfo 小工具的自訂 Logo（需先有 flclashx-servicename），支援 png/svg

**用法範例：**

```bash
flclashx-servicelogo: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/remnawave.svg
```

- flclashx-serverinfo：ChangeServerButton 小工具顯示的代理群組名稱，展示該群組內活躍節點（含國旗、延遲、快速切換）

**顯示元素：**
  - 國旗（自動辨識 serverDescription 或節點名稱）
  - 當前活躍節點名
  - 當前延遲（綠色 < 600 ms、橘色 ≥ 600 ms、紅色超時）
  - 快速跳轉鈕

**用法範例：**

```bash
flclashx-serverinfo: Proxy
```

- flclashx-background：為客戶端設定自訂背景圖，請提供直鏈

**建議規格：**
  - 格式：PNG、JPG 或 WebP
  - 解析度：桌機版 ≥1920×1080，手機版 1080×1920
  - 大小：2 MB 內
  - 內容：低飽和度漸層或紋理，避免太亮或花俏
  - 對比度：確保文字可讀

**用法範例：**

```bash
flclashx-background: https://example.com/background.jpg
```

- flclashx-settings：透過標頭統一管理客戶端設定（使用者可在本地開啟「覆蓋生產商設定」）。預設全部 **關閉**，帶入即 **開啟**

|      參數      | 說明                            | 預設狀態 |
| :----------:   | ------------------------------- | :----: |
|  `minimize`    | 關閉時縮到系統列而非結束程式     |  ❌ 關閉 |
|  `autorun`     | 開機自動啟動                     |  ❌ 關閉 |
| `shadowstart`  | 啟動後縮到背景                   |  ❌ 關閉 |
| `autostart`    | 啟動 App 後自動開啟代理          |  ❌ 關閉 |
| `autoupdate`   | 自動檢查更新                    |  ❌ 關閉 |

**客戶端覆蓋：** 可在「應用程式設定」啟用「覆蓋生產商設定」，以本地為主。

**用法範例：**

```bash
flclashx-settings: minimize,autorun,shadowstart,autostart,autoupdate
```

### 設定參數覆蓋規則

預設情況下，下列訂閱回傳參數**不會**被客戶端本地設定覆蓋：

- `allow-lan` - 允許區域網路連線
- `ipv6` - 啟用 IPv6
- `find-process-mode` - 行程搜尋模式
- `tun-stack` - TUN 網路堆疊
- `mixed-port` - HTTP/SOCKS 混合通訊埠

**客戶端覆蓋：** 可在「應用程式設定」內啟用「覆蓋生產商設定」或「覆蓋網路設定」，改以本地設定為準。

## 補充說明

### Linux

⚠️ 使用前請先安裝以下相依套件：

```bash
sudo apt-get install libayatana-appindicator3-dev
sudo apt-get install libkeybinder-3.0-dev
```

### Android

支援透過廣播控制：

```bash
com.follow.clashx.action.START   # 啟動代理
com.follow.clashx.action.STOP    # 停止代理
com.follow.clashx.action.CHANGE    # 切換節點
```

## 下載與安裝

<a href="https://github.com/pluralplay/FlClashX/releases"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## 贊助開發

<p style="text-align: center;">
點亮右上角的Star就是對開源項目最大的支持⭐<br>
若想小額捐贈，請<a href="https://t.me/tribute/app?startapp=dtyh">點擊此處</a>。
</p>

**TON USDT 地址：** `UQDSfrJ_k1BdsknhdR_zj4T3Is3OdMylD8PnDJ9mxO35i-TE`
