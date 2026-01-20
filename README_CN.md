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
[![Last Version](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![License](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClashX)

基于 ClashMeta 的跨平台代理工具 [FlClash](https://github.com/chen08209/FlClash) 的一个分支，简洁易用、开源无广。

桌面端预览：

<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

移动端预览：

<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## 修改日志

🛠️ **设置项**：进程搜索模式、TUN 模式、系统代理模式、代理列表显示模式设为"列表"；调整扫码添加订阅时的相机行为。

📱 **Android 120 Hz 高刷支持**：在Android上至高支持120Hz刷新率，德芙般丝滑(bushi)

🗑️ **清除应用数据**：应用设置内新增「清除数据」按钮，可一键删除 profiles 目录下所有配置，方便调试和重置。

🇷🇺 安装器新增俄语，应用内本地化重做。

✈️ 向面板传递 HWID（仅支持 <a href="https://github.com/remnawave/panel">Remnawave</a>）。

💻 新增「公告」小组件，可将面板公告推送至客户端（仅支持 <a href="https://github.com/remnawave/panel">Remnawave</a>）。

📺 Android TV 操作优化：

- URL添加菜单新增「粘贴」按钮
- 新增「选择配置」按钮
- 支持通过二维码将配置从手机端传输到电视端

🪪 配置卡片重做：

- 采用带颜色变化的流量指示器（无限流量时不显示）
- 显示订阅到期时间（年份为 2099 时显示「永久有效」）
- 配置页新增「客服」按钮，自动拉取面板 supportUrl
- 面板的 autoupdateinterval 参数现可正确下发

🪪 配置卡片新增「Meta-Info」、「serviceInfo」、「changeServerButton」小组件：

- 新增「Meta-Info」小组件：展示剩余流量、到期时间、配置名称，并在到期前 3 天突出显示剩余天数
- 新增「serviceInfo」小组件：展示服务名称；可额外传递 `flclashx-servicelogo` 头自定义 logo（支持 svg/png），点击跳转客服链接
- 新增「changeServerButton」小组件：点击后跳转至代理页

🌐 支持通过订阅页自定义头部进行解析：

- flclashx-widgets：按订阅返回的顺序排列小组件

  | 值                     | 对应小组件                                   |
  |----------------------|---------------------------------------------|
  | `announce`           | 公告图标                                   |
  | `networkSpeed`       | 逻辑速度                                       |
  | `outboundModeV2`     | 代理模式（新版）                           |
  | `outboundMode`       | 代理模式（旧版）                           |
  | `trafficUsage`       | 流量统计                                   |
  | `networkDetection`   | 位置与 IP 检测                            |
  | `tunButton`          | TUN 按钮（仅桌面端）                       |
  | `vpnButton`          | VPN 按钮（仅 Android）                     |
  | `systemProxyButton`  | 系统代理按钮（仅桌面端）                   |
  | `intranetIp`         | 局域网 IP                                  |
  | `memoryInfo`         | 内存占用                                   |
  | `metainfo`           | 配置信息                                   |
  | `changeServerButton` | 切换服务器按钮                             |
  | `serviceInfo`        | 服务信息（需配合 flclashx-servicename）    |

用法示例：

```bash
flclashx-widgets: announce,metainfo,outboundModeV2,networkDetection
```

- flclashx-view：可配置订阅返回的代理页外观

| 键      | 说明         | 可选值                     |
|---------|--------------|---------------------------|
| `type`  | 展示方式     | `list`、`tab`             |
| `sort`  | 排序方式     | `none`、`delay`、`name`   |
| `layout`| 布局        | `loose`、`standard`、`tight`      |
| `icon`| 图标风格（列表模式） | `none`、`icon`        |
| `card`| 卡片尺寸     | `expand`、`shrink`、`min`、`oneline` |

用法示例：

```bash
flclashx-view: type:list; sort:delay; layout:tight; icon:icon; card:shrink
```

- flclashx-custom：控制 Dashboard 与 ProxyView 的样式是否应用

| 值     | 说明                                   |
|--------|----------------------------------------|
| `add`  | 仅在首次添加订阅时应用样式             |
|`update`| 每次更新订阅均应用样式                  |

用法示例：

```bash
flclashx-custom: update
```

- flclashx-denywidgets：设为 true 时禁止编辑 Dashboard 页，接受 true/false

用法示例：

```bash
flclashx-denywidgets: true
```

- flclashx-servicename：服务信息（ServiceInfo）小组件显示的自定义服务名称

用法示例：

```bash
flclashx-servicename: FlClashX
```

- flclashx-servicelogo：ServiceInfo 小组件的自定义 logo（需 flclashx-servicename 存在），支持 png/svg

用法示例：

```bash
flclashx-servicelogo: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/remnawave.svg
```

- flclashx-serverinfo：ChangeServerButton 小组件显示的代理组名称，展示该组内活跃节点（带国旗、延迟、快速切换按钮）

**展示元素：**
  - 国旗（自动识别 serverDescription 或节点名称）
  - 活跃节点名称
  - 当前延迟（绿色 < 600 ms、橙色 ≥ 600 ms、红色超时）
  - 快速跳转按钮

**用法示例：**

```bash
flclashx-serverinfo: Proxy
```

- flclashx-background：为客户端设置自定义背景图，需提供直链

**推荐规范：**
  - 格式：PNG、JPG 或 WebP
  - 分辨率：桌面端 ≥1920×1080，移动端 1080×1920
  - 大小：控制在 2 MB 以内
  - 内容：使用低饱和度渐变或纹理，避免过亮或花哨
  - 对比度：保证文字可读性

**用法示例：**

```bash
flclashx-background: https://example.com/background.jpg
```

- flclashx-settings：通过头部统一管理客户端设置（用户可在本地开启「覆盖提供商设置」）。默认全部**关闭**，传入即**开启**

|     参数     | 说明                          | 默认状态 |
| :----------: | ----------------------------- | :------: |
|  `minimize`  | 退出时最小化到托盘而非关闭     |  ❌ 关闭   |
|  `autorun`   | 开机自启                      |  ❌ 关闭   |
|`shadowstart` | 启动后最小化                   |  ❌ 关闭   |
| `autostart`  | 启动应用后自动开启代理         |  ❌ 关闭   |
| `autoupdate` | 自动检查更新                   |  ❌ 关闭   |

**客户端覆盖：** 用户可在「应用设置」内开启「覆盖提供商配置」，以本地设置为准。

**用法示例：**

```bash
flclashx-settings: minimize,autorun,shadowstart,autostart,autoupdate
```

### 配置参数覆盖规则

默认情况下，订阅返回的以下参数**不会被客户端本地设置覆盖**：

- `allow-lan` - 允许局域网连接
- `ipv6` - 启用 IPv6
- `find-process-mode` - 进程搜索模式
- `tun-stack` - TUN 网络栈
- `mixed-port` - HTTP/SOCKS 混合端口

**客户端覆盖：** 用户可在「应用设置」内开启「覆盖提供商配置」或「覆盖网络设置」，以本地设置为准。

## 附加说明

### Linux

⚠️ 使用前请确保已安装以下依赖：

```bash
sudo apt-get install libayatana-appindicator3-dev
sudo apt-get install libkeybinder-3.0-dev
```

### Android

支持通过广播进行控制：

```bash
com.follow.clashx.action.START   # 启动代理
com.follow.clashx.action.STOP    # 停止代理
com.follow.clashx.action.CHANGE  # 切换节点
```

## 下载安装

<a href="https://github.com/pluralplay/FlClashX/releases"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## 支持开发

<p style="text-align: center;">
点亮项目右上角的的小星星就是对开源项目最大的支持⭐<br>
如愿意小额捐赠，可<a href="https://t.me/tribute/app?startapp=dtyh">点击此处</a>。
</p>

**TON USDT 地址：** `UQDSfrJ_k1BdsknhdR_zj4T3Is3OdMylD8PnDJ9mxO35i-TE`
