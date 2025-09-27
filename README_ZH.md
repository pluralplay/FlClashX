<div>

**README Languages**

[**🇺🇸 English**](README.md)  
[**🇷🇺 Русский**](README_RU.md)  
[**🇹🇼 繁体中文**](README_TW.md)  
[**🇯🇵 日本語**](README_JP.md)  

</div>

## FlClashX

[![下载量](https://img.shields.io/github/downloads/pluralplay/FlClashX/total?style=flat-square&logo=github)](https://github.com/pluralplay/FlClashX/releases/)
[![最新版本](https://img.shields.io/github/release/pluralplay/FlClashX/all.svg?style=flat-square)](https://github.com/pluralplay/FlClashX/releases/)
[![许可证](https://img.shields.io/github/license/pluralplay/FlClashX?style=flat-square)](LICENSE)

[![频道](https://img.shields.io/badge/Telegram-Chat-blue?style=flat-square&logo=telegram)](https://t.me/FlClash)

基于 ClashMeta 的多平台代理客户端 [FlClash](https://github.com/chen08209/FlClash) 的一个子分支，简单易用且开源无广告。

在桌面端：
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

在移动端：
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## 修改的功能：

🛠️ 修复默认设置：进程搜索模式开启，TUN 模式开启，系统代理模式关闭，代理列表显示模式设置为“列表”，添加订阅时的相机行为更改。

🇷🇺 为安装程序添加了俄语，并重新设计了应用程序内的本地化。

✈️ 将 HWID 传输到面板（仅适用于 <a href="">Remnawave</a>）。

💻 添加了新的“公告”小部件。它将面板的公告传输到小部件。（仅适用于 <a href="">Remnawave</a>）。

📺 优化了 Android TV 的控件。

+ 在菜单中添加了“粘贴”按钮，用于通过链接添加订阅。

+ 添加了配置文件选择按钮。

+ 添加了通过二维码将配置文件从移动应用程序传输的功能。

🪪 重新设计了配置文件卡片：

+ 使用带有变色流量条的流量金额（如果流量无限则不显示）。

+ 订阅到期日期（如果年份是 2099，则显示“永久订阅”）。

+ 在配置文件中添加了新的“支持”按钮，该按钮从面板中提取 supportUrl。

+ 配置文件的自动更新间隔现在可以正确地从面板传输。

🌐 添加了从订阅页面解析自定义标头：

+ flclashx-widgets：按从订阅接收的顺序排列小部件。

| 值  | 小部件名称 |
| :---: | ------------- |
| `announce`  | 公告Logo  |
| `networkSpeed`  | 网络速度 |
| `outboundModeV2`  | 代理模式（新类型）  |
| `outboundMode`  | 代理模式（旧类型）  |
| `trafficUsage`  | 流量使用情况  |
| `networkDetection`  | 检测位置和 IP  |
| `tunButton`  | TUN 按钮（仅限桌面端）  |
| `vpnButton`  | VPN 按钮（仅限 Android）  |
| `systemProxyButton`  | 系统代理按钮（仅限桌面端）  |
| `intranetIp`  | 内网 IP 地址 |
| `memoryInfo`  | 内存使用情况  |
| `metainfo`  | 配置文件信息  |




用法：
```bash
    flclashx-widgets: announce,metainfo,outboundModeV2,networkDetection
```
   + `flclashx-view`：配置从订阅获取的代理页面的外观。

| 值  | 描述 | 可能的值 |
| :---: | ------------- | ------------- |
| `type`  | 显示模式  | `list`,`tab` |
| `sort`  | 排序类型	  | `none`,`delay`,`name`|
| `layout`  | 布局  | `loose`,`standard`,`tight` |
| `icon`  | 图标样式（用于列表显示）  | `none`,`standard`,`icon` |
| `card`  | 卡片大小   | `expand`,`shrink`,`min` |


用法：
```bash
    flclashx-view: type:list; sort:delay; layout:tight; icon:standard; card:shrink
```

   + `flclashx-custom`：控制 Dashboard 和 ProxyView 样式的应用。

| 值  | 描述 |
| :---: | ------------- |
| `add`  | 样式仅在首次添加订阅时应用  |
| `update`  | 	每次更新订阅时都应用样式 |

用法：
```bash
    flclashx-custom: update
```
   + `flclashx-denywidgets`：设置为 true 时，禁用编辑 Dashboard 页面。接受 true/false。

用法：
```bash
    flclashx-denywidgets: true
```

## 应用程序使用

### Linux
⚠️ 使用前，请确保已安装以下依赖项：
   ```bash
    sudo apt-get install libayatana-appindicator3-dev
    sudo apt-get install libkeybinder-3.0-dev
   ```
### Android
支持以下操作：
   ```bash
    com.follow.clashx.action.START
  
    com.follow.clashx.action.STOP
  
    com.follow.clashx.action.CHANGE
   ```


## 下载
<a href=""><img alt="在 GitHub 上获取" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## 支持开发
<p style="text-align: center;">
如果您喜欢此项目，可以在右上角送开发者一颗小星星 (⭐)。<br>
如果您想通过小额捐赠来支持开发，请<a href="">点这里</a>。
</p>

**TON USDT:** `UQDSfrJ_k1BdsknhdR_zj4T3Is3OdMylD8PnDJ9mxO35i-TE`

## 译者

Chinese Translation/中文译者: [Heliumray](https://github.com/heliumray)
