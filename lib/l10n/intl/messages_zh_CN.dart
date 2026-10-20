// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a zh_CN locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(count, skipped) => "将添加 ${count} 项，跳过 ${skipped} 项已存在";

  static String m1(detail) => "清除数据失败：${detail}";

  static String m2(code) =>
      "Windows 拒绝运行 FlClashCore.exe（错误 ${code}）。智能应用控制、AppLocker 等应用控制策略会拦截未签名程序，请在该策略中放行 FlClashX 或关闭策略后重试。";

  static String m3(name) =>
      "应用连续两次未能完成启动。为打断崩溃循环，已取消选中配置 ${name}，并跳过本次自动配置，你可以随时重新选中它。";

  static String m4(url) => "是否要通过 ${url} 创建配置？";

  static String m5(count, label) =>
      "${Intl.plural(count, other: '自定义配置不支持子规则，已丢弃 ${label} 条 SUB-RULE 规则')}";

  static String m6(message) => "内核无法解析该代理：${message}";

  static String m7(proxy, target) =>
      "${proxy} 经 ${target} 拨号，而 ${target} 又会回到 ${proxy}，形成环路";

  static String m8(name) => "名称 ${name} 已被其他代理或策略组使用";

  static String m9(path) => "策略组之间存在循环引用：${path}";

  static String m10(name) => "空组兜底只能是代理，${name} 不存在或是策略组";

  static String m11(name, message) => "${name}不是有效的正则：${message}";

  static String m12(name) => "拨号代理 ${name} 不存在";

  static String m13(names) => "以下代理集不存在：${names}";

  static String m14(names) => "以下代理或策略不存在：${names}";

  static String m15(name) => "${name} 是内置策略名，不能在此使用";

  static String m16(count) => "${count} 项存在问题，应用配置可能失败";

  static String m17(count) => "${count} 天前";

  static String m18(count) => "${count} 天前";

  static String m19(label) => "确定删除选中的${label}吗？";

  static String m20(label) => "确定删除当前${label}吗？";

  static String m21(label) => "${label}详情";

  static String m22(name) => "经 ${name} 拨号会绕回使用它的代理，连接已中止";

  static String m23(label) => "${label}不能为空";

  static String m24(label) => "${label}当前已存在";

  static String m25(address) => "外部控制器开启后，可通过 ${address} 控制内核。";

  static String m26(count) => "${count} 项失败";

  static String m27(label, message) => "${label}：${message}";

  static String m28(name) => "${name} 已是最新版本";

  static String m29(name) => "${name} 已更新";

  static String m30(count) => "${count} 个";

  static String m31(count) => "${count} 超时";

  static String m32(action) => "已被“${action}”使用，保存后将移到这里";

  static String m33(modifiers) => "至少包含 ${modifiers} 中的一个";

  static String m34(count) => "${count} 小时前";

  static String m35(count) => "${count} 小时前";

  static String m36(target) => "${target} 是一个无效的策略";

  static String m37(proxyName) => "${proxyName} 是一个无效的代理";

  static String m38(providerName) => "${providerName} 是一个无效的代理集";

  static String m39(ruleSet) => "${ruleSet} 不是有效的规则集";

  static String m40(subRule) => "${subRule} 是一个无效的SUB_RULE";

  static String m41(count) => "${count} 项";

  static String m42(line, message) => "第 ${line} 行：${message}";

  static String m43(appName) =>
      "1. 打开 系统设置 > 隐私与安全性\n2. 选择 定位服务\n3. 在右侧列表中找到并勾选 ${appName}\n\n完成设置后，返回应用即可正常使用。感谢您的配合。";

  static String m44(label, max) => "${label}最多${max}个字符";

  static String m45(size) => "已释放 ${size}";

  static String m46(count) => "${count} 分钟前";

  static String m47(count) => "${count} 分钟前";

  static String m48(count) => "${count} 个月前";

  static String m49(count) => "${count} 个月前";

  static String m50(code) => "服务器拒绝访问（HTTP ${code}），链接可能已过期或凭据有误";

  static String m51(code) => "服务器拒绝了请求（HTTP ${code}）";

  static String m52(code) => "该地址下没有内容（HTTP ${code}），请确认链接是否正确";

  static String m53(detail) => "网络请求失败：${detail}";

  static String m54(code) => "服务器出现问题（HTTP ${code}），请稍后再试";

  static String m55(label) => "暂无${label}";

  static String m56(label, min, max) => "${label}必须在 ${min} 到 ${max} 之间";

  static String m57(label) => "${label}必须为数字";

  static String m58(label) => "${label} 必须在 1024 到 49151 之间";

  static String m59(port) => "端口 ${port}";

  static String m60(days) => "${days} 天";

  static String m61(days) => "剩余 ${days} 天";

  static String m62(date, days) => "${date} 到期，剩余 ${days} 天";

  static String m63(hours) => "${hours} 小时";

  static String m64(total) => "剩余 / ${total}";

  static String m65(minutes) => "${minutes} 分钟";

  static String m66(date) => "至 ${date}";

  static String m67(time) => "更新于 ${time}";

  static String m68(label, profiles) =>
      "${label} 仍被 ${profiles} 使用，删除后这些配置会异常。确定删除吗？";

  static String m69(count, label) =>
      "${Intl.plural(count, other: '${label} 个代理')}";

  static String m70(name, count) => "${name} 等 ${count} 个代理";

  static String m71(removed) =>
      "以下代理将被删除：${removed}。改了名字的行按新代理处理，自定义配置中对被删除代理的引用会标为缺失。确定应用吗？";

  static String m72(removed, added) =>
      "以下代理将被删除：${removed}。以下代理将新增：${added}。改了名字的行按新代理处理，自定义配置中对被删除代理的引用会标为缺失。确定应用吗？";

  static String m73(label) =>
      "${label} 仍被当前配置的规则、策略组、拨号代理、DNS 或 NTP 引用，删除后这些引用会失效。确定删除吗？";

  static String m74(count, label) =>
      "${Intl.plural(count, other: '${label} 个策略组')}";

  static String m75(count, label) =>
      "${Intl.plural(count, other: '${label} 条规则')}";

  static String m76(appName) => "${appName}（安全模式）";

  static String m77(count) => "${count} 秒";

  static String m78(count) => "${count} 项生效";

  static String m79(count) => "${count} 项异常";

  static String m80(time) => "检测于 ${time}";

  static String m81(count) => "${count} 项设置";

  static String m82(link) => "无法从 ${link} 中读取代理";

  static String m83(label) => "${label}只能是一项";

  static String m84(days) => "您的订阅将在 ${days} 天后到期";

  static String m85(value) => "峰值 ${value}";

  static String m86(value) => "累计 ${value}";

  static String m87(label) => "${label}必须为URL";

  static String m88(count) => "${count} 年前";

  static String m89(count) => "${count} 年前";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("关于"),
    "accessControl": MessageLookupByLibrary.simpleMessage("访问控制"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "只允许选中应用进入VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "访问控制决定哪些应用使用代理。",
    ),
    "accessControlDisabledDesc": MessageLookupByLibrary.simpleMessage(
      "应用访问控制已关闭",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "选中应用将会被排除在VPN之外",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage("访问控制设置"),
    "account": MessageLookupByLibrary.simpleMessage("账号"),
    "action": MessageLookupByLibrary.simpleMessage("操作"),
    "actionDelayTest": MessageLookupByLibrary.simpleMessage("测试全部延迟"),
    "actionDirectMode": MessageLookupByLibrary.simpleMessage("直连模式"),
    "actionGlobalMode": MessageLookupByLibrary.simpleMessage("全局模式"),
    "actionMode": MessageLookupByLibrary.simpleMessage("切换模式"),
    "actionProxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "actionRuleMode": MessageLookupByLibrary.simpleMessage("规则模式"),
    "actionStart": MessageLookupByLibrary.simpleMessage("启动/停止"),
    "actionTun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "actionUpdateProfiles": MessageLookupByLibrary.simpleMessage("更新全部配置"),
    "actionView": MessageLookupByLibrary.simpleMessage("显示/隐藏"),
    "add": MessageLookupByLibrary.simpleMessage("添加"),
    "addCustomProxy": MessageLookupByLibrary.simpleMessage("添加代理"),
    "addFilters": MessageLookupByLibrary.simpleMessage("添加筛选"),
    "addNodes": MessageLookupByLibrary.simpleMessage("添加节点"),
    "addOverrideEntry": MessageLookupByLibrary.simpleMessage("添加覆写项"),
    "addProfile": MessageLookupByLibrary.simpleMessage("添加配置"),
    "addProfileFromClipboard": MessageLookupByLibrary.simpleMessage("从剪贴板添加配置"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("添加策略组"),
    "addRule": MessageLookupByLibrary.simpleMessage("添加规则"),
    "addSettingEntry": MessageLookupByLibrary.simpleMessage("添加设置项"),
    "addSsid": MessageLookupByLibrary.simpleMessage("添加SSID"),
    "addedRules": MessageLookupByLibrary.simpleMessage("附加规则"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage("附加参数"),
    "additionalPrefix": MessageLookupByLibrary.simpleMessage("名称前缀"),
    "additionalSuffix": MessageLookupByLibrary.simpleMessage("名称后缀"),
    "address": MessageLookupByLibrary.simpleMessage("地址"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("WebDAV服务器地址"),
    "addressTip": MessageLookupByLibrary.simpleMessage("请输入有效的WebDAV地址"),
    "advancedConfig": MessageLookupByLibrary.simpleMessage("进阶配置"),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "进阶配置包含网络、DNS、附加规则与脚本。",
    ),
    "ageEncryptedProfile": MessageLookupByLibrary.simpleMessage("配置已加密"),
    "ageSecretKey": MessageLookupByLibrary.simpleMessage("age 私钥"),
    "ageSecretKeyRequiredTip": MessageLookupByLibrary.simpleMessage(
      "该配置已用 age 加密，需要 age 私钥才能解密",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("我同意"),
    "allReferencedProxies": MessageLookupByLibrary.simpleMessage("全部被引用的代理"),
    "allReferencedProxyProviders": MessageLookupByLibrary.simpleMessage(
      "全部被引用的代理集",
    ),
    "allowBypass": MessageLookupByLibrary.simpleMessage("允许应用绕过VPN"),
    "allowLan": MessageLookupByLibrary.simpleMessage("局域网代理"),
    "allowedIps": MessageLookupByLibrary.simpleMessage("允许的 IP"),
    "announcement": MessageLookupByLibrary.simpleMessage("公告"),
    "answers": MessageLookupByLibrary.simpleMessage("应答"),
    "app": MessageLookupByLibrary.simpleMessage("应用"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage("应用访问控制"),
    "appIconDesign": MessageLookupByLibrary.simpleMessage("应用图标设计"),
    "appProxiesEmpty": MessageLookupByLibrary.simpleMessage("暂无本地代理"),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage("追加系统DNS"),
    "authentication": MessageLookupByLibrary.simpleMessage("认证"),
    "authenticationDesc": MessageLookupByLibrary.simpleMessage(
      "认证开启后，使用本地代理端口需要账号密码。",
    ),
    "authenticationSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "认证启用时，系统代理不生效。",
    ),
    "authorize": MessageLookupByLibrary.simpleMessage("授权"),
    "authorized": MessageLookupByLibrary.simpleMessage("已授权"),
    "auto": MessageLookupByLibrary.simpleMessage("自动"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage("自动检查更新"),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage("自动关闭连接"),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "自动关闭连接会在切换代理后断开已有连接。",
    ),
    "autoInclude": MessageLookupByLibrary.simpleMessage("自动包含"),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("自启动"),
    "autoRun": MessageLookupByLibrary.simpleMessage("自动运行"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage("自动运行会在打开应用时启动代理。"),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage("自动设置系统DNS"),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("自动更新"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage("自动更新间隔"),
    "back": MessageLookupByLibrary.simpleMessage("返回"),
    "backup": MessageLookupByLibrary.simpleMessage("备份"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage("备份与恢复"),
    "backupFromNewerVersion": MessageLookupByLibrary.simpleMessage(
      "该备份来自更高版本的应用，请先更新应用再恢复",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("备份成功"),
    "basicInfo": MessageLookupByLibrary.simpleMessage("基础信息"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("基础策略"),
    "batchAdd": MessageLookupByLibrary.simpleMessage("批量添加"),
    "batchImport": MessageLookupByLibrary.simpleMessage("批量导入"),
    "batchLinkInputTip": MessageLookupByLibrary.simpleMessage("每行一个链接"),
    "batchListInputTip": MessageLookupByLibrary.simpleMessage("每行一项，也可用逗号分隔"),
    "batchMapInputTip": MessageLookupByLibrary.simpleMessage("每行一条，键和值之间用空格分隔"),
    "batchPreviewTip": m0,
    "batchUrlInputTip": MessageLookupByLibrary.simpleMessage("每行一个URL"),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "忽略电池优化可保证应用在后台运行。",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("绑定"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("黑名单模式"),
    "blockConnection": MessageLookupByLibrary.simpleMessage("阻止连接"),
    "brightness": MessageLookupByLibrary.simpleMessage("亮度"),
    "buyPlan": MessageLookupByLibrary.simpleMessage("续订"),
    "buyTraffic": MessageLookupByLibrary.simpleMessage("购买流量"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("排除域名"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "排除域名仅在系统代理启用时生效。",
    ),
    "bypassPrivateRoute": MessageLookupByLibrary.simpleMessage("绕过私有路由地址"),
    "bypassPrivateRouteDesc": MessageLookupByLibrary.simpleMessage(
      "开启绕过私有路由地址后，局域网、回环和组播地址不经过虚拟网卡。",
    ),
    "cache": MessageLookupByLibrary.simpleMessage("缓存"),
    "cacheAlgorithm": MessageLookupByLibrary.simpleMessage("缓存算法"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage("缓存已损坏，是否清空？"),
    "cacheMaxSize": MessageLookupByLibrary.simpleMessage("缓存大小"),
    "cameraPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "请在系统设置中允许访问相机以扫描二维码，或从相册选择二维码图片。",
    ),
    "cameraPermissionRequired": MessageLookupByLibrary.simpleMessage("需要相机权限"),
    "cameraUnavailable": MessageLookupByLibrary.simpleMessage("相机不可用"),
    "cancel": MessageLookupByLibrary.simpleMessage("取消"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("取消全选"),
    "cannotSave": MessageLookupByLibrary.simpleMessage("无法保存"),
    "changeProxyFailedTip": MessageLookupByLibrary.simpleMessage(
      "切换代理失败，已恢复上一次的选择",
    ),
    "changeServer": MessageLookupByLibrary.simpleMessage("切换服务器"),
    "changelogBreaking": MessageLookupByLibrary.simpleMessage("重大变更"),
    "changelogFeatures": MessageLookupByLibrary.simpleMessage("新功能"),
    "changelogFixes": MessageLookupByLibrary.simpleMessage("问题修复"),
    "changelogPerformance": MessageLookupByLibrary.simpleMessage("性能优化"),
    "changelogReverts": MessageLookupByLibrary.simpleMessage("已回滚"),
    "checkCertificate": MessageLookupByLibrary.simpleMessage("校验 TLS 证书"),
    "checkCertificateDesc": MessageLookupByLibrary.simpleMessage(
      "关闭证书校验后，订阅和备份可能遭中间人攻击。",
    ),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("检查更新"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage("当前应用已经是最新版了"),
    "cipher": MessageLookupByLibrary.simpleMessage("加密方式"),
    "clearData": MessageLookupByLibrary.simpleMessage("清除数据"),
    "clearDataAndExitTip": MessageLookupByLibrary.simpleMessage(
      "将删除所有配置、设置和本地数据，随后关闭应用。重新打开即可从头开始。",
    ),
    "clearDataFailed": m1,
    "clearSearch": MessageLookupByLibrary.simpleMessage("清除搜索"),
    "clientFingerprint": MessageLookupByLibrary.simpleMessage("客户端指纹"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("导出剪贴板"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("剪贴板导入"),
    "clipboardWriteFailed": MessageLookupByLibrary.simpleMessage(
      "无法复制到剪贴板，所选内容可能过大",
    ),
    "close": MessageLookupByLibrary.simpleMessage("关闭"),
    "closeConnections": MessageLookupByLibrary.simpleMessage("关闭连接"),
    "color": MessageLookupByLibrary.simpleMessage("颜色"),
    "colorStyle": MessageLookupByLibrary.simpleMessage("配色风格"),
    "columns": MessageLookupByLibrary.simpleMessage("列数"),
    "compact": MessageLookupByLibrary.simpleMessage("紧凑"),
    "compatible": MessageLookupByLibrary.simpleMessage("兼容模式"),
    "confirm": MessageLookupByLibrary.simpleMessage("确定"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage("确定要清除所有数据？"),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "确定要删除当前策略组吗？",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage("确定要退出当前窗口吗？"),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage("确定要强制崩溃核心？"),
    "congestionControl": MessageLookupByLibrary.simpleMessage("拥塞控制"),
    "congestionController": MessageLookupByLibrary.simpleMessage("TCP 拥塞控制"),
    "congestionControllerDesc": MessageLookupByLibrary.simpleMessage(
      "TCP 拥塞控制仅在 mips 栈生效。",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("已连接"),
    "connecting": MessageLookupByLibrary.simpleMessage("连接中…"),
    "connection": MessageLookupByLibrary.simpleMessage("连接"),
    "connectionStats": MessageLookupByLibrary.simpleMessage("连接统计"),
    "connectionStatsDesc": MessageLookupByLibrary.simpleMessage(
      "实时连接、最近请求、DNS查询",
    ),
    "connections": MessageLookupByLibrary.simpleMessage("连接"),
    "connectivity": MessageLookupByLibrary.simpleMessage("连通性："),
    "content": MessageLookupByLibrary.simpleMessage("内容"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage("内容不能为空"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage("控制全局附加规则"),
    "copy": MessageLookupByLibrary.simpleMessage("复制"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage("复制环境变量"),
    "copyLink": MessageLookupByLibrary.simpleMessage("复制链接"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("复制成功"),
    "core": MessageLookupByLibrary.simpleMessage("内核"),
    "coreBlockedByPolicyTip": m2,
    "coreBlockedBySmartAppControlTip": MessageLookupByLibrary.simpleMessage(
      "Windows 智能应用控制拦截了未签名的 FlClashCore.exe。请打开 Windows 安全中心 → 应用和浏览器控制 → 智能应用控制设置，选择「关闭」后重新启动 FlClashX。智能应用控制关闭后无法再开启，除非重装 Windows。",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("核心状态"),
    "country": MessageLookupByLibrary.simpleMessage("区域"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("检测到崩溃"),
    "crashDetectedTip": m3,
    "crashTest": MessageLookupByLibrary.simpleMessage("崩溃测试"),
    "create": MessageLookupByLibrary.simpleMessage("创建"),
    "createProfileFromUrlTip": m4,
    "creationTime": MessageLookupByLibrary.simpleMessage("创建时间"),
    "currentOutboundDesc": MessageLookupByLibrary.simpleMessage("含启动键，不可移除"),
    "custom": MessageLookupByLibrary.simpleMessage("自定义"),
    "customColor": MessageLookupByLibrary.simpleMessage("自定义颜色"),
    "customImportDroppedSubRules": m5,
    "customIssueCoreRejected": m6,
    "customIssueDialerLoop": m7,
    "customIssueDuplicateName": m8,
    "customIssueEmptyName": MessageLookupByLibrary.simpleMessage("名称为空"),
    "customIssueGroupLoop": m9,
    "customIssueInvalidEmptyFallback": m10,
    "customIssueInvalidFilter": m11,
    "customIssueMissingDialer": m12,
    "customIssueMissingProviders": m13,
    "customIssueMissingProxies": m14,
    "customIssueNoProxySource": MessageLookupByLibrary.simpleMessage(
      "未选择任何代理或代理集，内核会拒绝该策略组",
    ),
    "customIssueReservedName": m15,
    "customIssuesSummary": m16,
    "customProfile": MessageLookupByLibrary.simpleMessage("自定义"),
    "customProfileDesc": MessageLookupByLibrary.simpleMessage(
      "基于应用代理和其他配置组建策略组与规则",
    ),
    "customProfileResources": MessageLookupByLibrary.simpleMessage("自定义配置资源"),
    "customProfileResourcesDesc": MessageLookupByLibrary.simpleMessage(
      "自定义配置资源包含代理、规则集、筛选与图标集。",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("剪切"),
    "dark": MessageLookupByLibrary.simpleMessage("深色"),
    "dashboard": MessageLookupByLibrary.simpleMessage("仪表盘"),
    "dashboardAddableSection": MessageLookupByLibrary.simpleMessage("可添加"),
    "databaseWriteFailedTip": MessageLookupByLibrary.simpleMessage(
      "保存更改失败，已回滚",
    ),
    "daysAgo": m17,
    "daysAgoShort": m18,
    "defaultSelected": MessageLookupByLibrary.simpleMessage("默认选中"),
    "defaultText": MessageLookupByLibrary.simpleMessage("默认"),
    "definitionNotMap": MessageLookupByLibrary.simpleMessage(
      "配置必须是包含 name 和 type 的 YAML 映射",
    ),
    "delay": MessageLookupByLibrary.simpleMessage("延迟"),
    "delayFailed": MessageLookupByLibrary.simpleMessage("失败"),
    "delayTest": MessageLookupByLibrary.simpleMessage("延迟测试"),
    "delayTestAll": MessageLookupByLibrary.simpleMessage("测试全部延迟"),
    "delete": MessageLookupByLibrary.simpleMessage("删除"),
    "deleteMultipTip": m19,
    "deleteTip": m20,
    "desc": MessageLookupByLibrary.simpleMessage(
      "基于Mihomo的多平台代理客户端，简单易用，开源无广告。",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("目标地址"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage("目标地理定位"),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage("目标IP ASN"),
    "details": m21,
    "detectionTip": MessageLookupByLibrary.simpleMessage("使用第三方 API：ipinfo.io"),
    "developerMode": MessageLookupByLibrary.simpleMessage("开发者模式"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage("开发者模式已启用。"),
    "deviceIdNotSent": MessageLookupByLibrary.simpleMessage(
      "该订阅需要 HWID，但应用未发送。请在配置设置中开启发送 HWID。",
    ),
    "deviceIdUnsupported": MessageLookupByLibrary.simpleMessage(
      "该订阅需要 HWID，但此平台无法提供。",
    ),
    "deviceIdUnsupportedTitle": MessageLookupByLibrary.simpleMessage(
      "不支持 HWID",
    ),
    "deviceLimitReached": MessageLookupByLibrary.simpleMessage("已达到设备数量上限"),
    "dialerProxy": MessageLookupByLibrary.simpleMessage("拨号代理"),
    "dialerProxyDesc": MessageLookupByLibrary.simpleMessage(
      "拨号代理为连接 NTP 服务器使用的出站。",
    ),
    "dialerProxyLoopStopped": m22,
    "direct": MessageLookupByLibrary.simpleMessage("直连"),
    "disableIcmpForwarding": MessageLookupByLibrary.simpleMessage("禁用ICMP转发"),
    "disableIcmpForwardingDesc": MessageLookupByLibrary.simpleMessage(
      "禁用 ICMP 转发后由虚拟网卡直接应答 ping，ping 将不再显示真实延迟。",
    ),
    "disableKeepAlive": MessageLookupByLibrary.simpleMessage("禁用 TCP 保持活动"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("禁用UDP"),
    "disabled": MessageLookupByLibrary.simpleMessage("已关闭"),
    "discardChanges": MessageLookupByLibrary.simpleMessage("是否放弃更改？"),
    "disclaimer": MessageLookupByLibrary.simpleMessage("免责声明"),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "FlClashX 是基于 Mihomo 内核的免费开源客户端。下面简要说明它做什么、不做什么以及收集哪些数据。点击“我同意”即表示接受这些条款。",
    ),
    "disclaimerLicenseContent": MessageLookupByLibrary.simpleMessage(
      "源代码以 GPL-3.0 许可证开放。Mihomo 内核及其他第三方组件使用各自的许可证。作者不对经修改或由第三方分发的版本负责。",
    ),
    "disclaimerLicenseTitle": MessageLookupByLibrary.simpleMessage("许可证"),
    "disclaimerPrivacyContent": MessageLookupByLibrary.simpleMessage(
      "为排查问题，本程序通过 Google Firebase 收集技术数据：崩溃报告、程序和系统版本、设备型号以及匿名的功能使用统计。\n\n订阅链接、配置内容、服务器、访问过的网站、连接、流量和日志不会被收集，也不会发送到任何地方，它们只保存在您的设备上。",
    ),
    "disclaimerPrivacyTitle": MessageLookupByLibrary.simpleMessage("数据"),
    "disclaimerResponsibilityContent": MessageLookupByLibrary.simpleMessage(
      "在您所在国家或地区使用本程序是否合法由您自行判断，您对自己的使用行为负责。\n\n本程序按“现状”提供，不作任何保证。开发者不对因使用或无法使用本程序造成的损失负责，也不对第三方订阅、配置和链接负责。",
    ),
    "disclaimerResponsibilityTitle": MessageLookupByLibrary.simpleMessage("责任"),
    "disclaimerSoftwareContent": MessageLookupByLibrary.simpleMessage(
      "本程序只在您的设备上管理配置并按规则转发流量。\n\n我们不出售任何东西，也不提供代理服务器、节点、订阅或网络接入。所有服务器和订阅均来自第三方提供者，其合法性、安全性和质量由您与提供者自行解决。本程序与此类提供者无关，也不为其负责。",
    ),
    "disclaimerSoftwareTitle": MessageLookupByLibrary.simpleMessage(
      "它是什么，不是什么",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("已断开"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage("发现新版本"),
    "dnsHijackDesc": MessageLookupByLibrary.simpleMessage(
      "未添加时劫持所有发往 53 端口的 DNS 请求（any:53）。",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNS劫持"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS模式"),
    "dnsOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "添加的项会覆写所有 URL 和文件配置的 DNS，未添加的项沿用配置自身的设置。自定义配置的 DNS 在其内容中设置。",
    ),
    "dnsQueries": MessageLookupByLibrary.simpleMessage("DNS查询"),
    "docked": MessageLookupByLibrary.simpleMessage("固定"),
    "domain": MessageLookupByLibrary.simpleMessage("域名"),
    "done": MessageLookupByLibrary.simpleMessage("完成"),
    "download": MessageLookupByLibrary.simpleMessage("下载"),
    "downloadBandwidth": MessageLookupByLibrary.simpleMessage("下行带宽"),
    "duration": MessageLookupByLibrary.simpleMessage("时长"),
    "edit": MessageLookupByLibrary.simpleMessage("编辑"),
    "editDashboard": MessageLookupByLibrary.simpleMessage("编辑仪表盘"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage("编辑全局规则"),
    "editProxy": MessageLookupByLibrary.simpleMessage("编辑代理"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("编辑策略组"),
    "editRule": MessageLookupByLibrary.simpleMessage("编辑规则"),
    "editSsid": MessageLookupByLibrary.simpleMessage("编辑SSID"),
    "editorUnavailable": MessageLookupByLibrary.simpleMessage("编辑器不可用"),
    "elapsed": MessageLookupByLibrary.simpleMessage("耗时"),
    "emptyFallback": MessageLookupByLibrary.simpleMessage("空组兜底"),
    "emptyTip": m23,
    "en": MessageLookupByLibrary.simpleMessage("英语"),
    "enabled": MessageLookupByLibrary.simpleMessage("已开启"),
    "entries": MessageLookupByLibrary.simpleMessage("个条目"),
    "error": MessageLookupByLibrary.simpleMessage("错误"),
    "errorDetails": MessageLookupByLibrary.simpleMessage("错误详情"),
    "es": MessageLookupByLibrary.simpleMessage("西班牙语"),
    "exclude": MessageLookupByLibrary.simpleMessage("从最近任务中隐藏"),
    "excludeDstPort": MessageLookupByLibrary.simpleMessage("排除目标端口"),
    "excludeDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "发往这些目标端口的流量不经过虚拟网卡。",
    ),
    "excludeFilter": MessageLookupByLibrary.simpleMessage("排除筛选"),
    "excludeInterface": MessageLookupByLibrary.simpleMessage("排除网卡"),
    "excludeInterfaceDesc": MessageLookupByLibrary.simpleMessage(
      "从这些网卡（如 docker0）进入的流量不经过虚拟网卡。",
    ),
    "excludeSrcPort": MessageLookupByLibrary.simpleMessage("排除源端口"),
    "excludeSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "源端口为这些端口的流量不经过虚拟网卡。",
    ),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("排除SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "连接到被排除 SSID 的 Wi-Fi 时，将会自动切换应用运行状态。",
    ),
    "excludeUid": MessageLookupByLibrary.simpleMessage("排除用户 ID"),
    "excludeUidDesc": MessageLookupByLibrary.simpleMessage(
      "这些用户 ID 的进程产生的流量不经过虚拟网卡。",
    ),
    "existsTip": m24,
    "exit": MessageLookupByLibrary.simpleMessage("退出"),
    "exitFullScreen": MessageLookupByLibrary.simpleMessage("退出全屏"),
    "exitNodes": MessageLookupByLibrary.simpleMessage("出口节点"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("预期状态"),
    "expireTime": MessageLookupByLibrary.simpleMessage("到期时间"),
    "exportFile": MessageLookupByLibrary.simpleMessage("导出文件"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("导出日志"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("导出成功"),
    "extend": MessageLookupByLibrary.simpleMessage("扩展"),
    "extendMode": MessageLookupByLibrary.simpleMessage("扩展模式"),
    "extendScript": MessageLookupByLibrary.simpleMessage("扩展脚本"),
    "externalController": MessageLookupByLibrary.simpleMessage("外部控制器"),
    "externalControllerDesc": m25,
    "externalControllerSecret": MessageLookupByLibrary.simpleMessage("外部控制器密钥"),
    "externalLink": MessageLookupByLibrary.simpleMessage("外部链接"),
    "extraLarge": MessageLookupByLibrary.simpleMessage("超大"),
    "fade": MessageLookupByLibrary.simpleMessage("淡入"),
    "failedCount": m26,
    "failedItem": m27,
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fake-IP过滤"),
    "fakeipFilterMode": MessageLookupByLibrary.simpleMessage("Fake-IP过滤模式"),
    "fakeipFilterModeDesc": MessageLookupByLibrary.simpleMessage(
      "Fake-IP 过滤模式中，blacklist 排除匹配项，whitelist 仅用于匹配项，rule 按规则匹配。",
    ),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fake-IP范围"),
    "fakeipRange6": MessageLookupByLibrary.simpleMessage("Fake-IP范围（IPv6）"),
    "fakeipTtl": MessageLookupByLibrary.simpleMessage("Fake-IP TTL"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback过滤"),
    "file": MessageLookupByLibrary.simpleMessage("文件"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("直接上传配置文件"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage("文件有修改，是否保存修改"),
    "filter": MessageLookupByLibrary.simpleMessage("筛选"),
    "filters": MessageLookupByLibrary.simpleMessage("筛选"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("查找进程"),
    "floating": MessageLookupByLibrary.simpleMessage("悬浮"),
    "foldAllGroups": MessageLookupByLibrary.simpleMessage("收起所有分组"),
    "followProfile": MessageLookupByLibrary.simpleMessage("跟随配置"),
    "followSystem": MessageLookupByLibrary.simpleMessage("跟随系统"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("字体"),
    "fontSize": MessageLookupByLibrary.simpleMessage("大小"),
    "forceDnsMapping": MessageLookupByLibrary.simpleMessage("强制DNS映射"),
    "forceDnsMappingDesc": MessageLookupByLibrary.simpleMessage(
      "强制 DNS 映射对通过 DNS 映射得到域名的连接也进行嗅探。",
    ),
    "forceDomain": MessageLookupByLibrary.simpleMessage("强制嗅探域名"),
    "forceDomainDesc": MessageLookupByLibrary.simpleMessage(
      "强制嗅探域名中的域名同样会被嗅探，其余已有域名的连接不嗅探。",
    ),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage("您确定要强制重启核心吗？"),
    "fr": MessageLookupByLibrary.simpleMessage("法语"),
    "general": MessageLookupByLibrary.simpleMessage("常规"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geo"),
    "geoSkipped": m28,
    "geoUpdated": m29,
    "geodataLoader": MessageLookupByLibrary.simpleMessage("Geo低内存模式"),
    "global": MessageLookupByLibrary.simpleMessage("全局"),
    "go": MessageLookupByLibrary.simpleMessage("前往"),
    "goDownload": MessageLookupByLibrary.simpleMessage("前往下载"),
    "goToConfigureAddedRules": MessageLookupByLibrary.simpleMessage("前往配置附加规则"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage("前往配置脚本"),
    "gratitude": MessageLookupByLibrary.simpleMessage("致谢"),
    "grid": MessageLookupByLibrary.simpleMessage("网格"),
    "groupCount": m30,
    "groupCountUnit": MessageLookupByLibrary.simpleMessage("个"),
    "groupTimeoutCount": m31,
    "hasCacheChange": MessageLookupByLibrary.simpleMessage("是否缓存修改"),
    "hashByInUser": MessageLookupByLibrary.simpleMessage("按入站用户哈希"),
    "healthCheck": MessageLookupByLibrary.simpleMessage("健康检查"),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper 服务不可用，无法启用 TUN 模式，请重新安装 FlClashX。",
    ),
    "hex": MessageLookupByLibrary.simpleMessage("十六进制"),
    "hideFromList": MessageLookupByLibrary.simpleMessage("从列表中隐藏"),
    "hideIp": MessageLookupByLibrary.simpleMessage("隐藏 IP"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("隐藏密码"),
    "hideTimeoutProxies": MessageLookupByLibrary.simpleMessage("隐藏超时代理"),
    "hideTimeoutProxiesDesc": MessageLookupByLibrary.simpleMessage(
      "不显示上次延迟测试超时的代理",
    ),
    "hopInterval": MessageLookupByLibrary.simpleMessage("跳跃间隔"),
    "host": MessageLookupByLibrary.simpleMessage("主机"),
    "hostname": MessageLookupByLibrary.simpleMessage("主机名"),
    "hotkeyConflictWith": m32,
    "hotkeyDesc": MessageLookupByLibrary.simpleMessage(
      "全局快捷键在窗口隐藏时依然生效，点击操作即可录制组合键。",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("快捷键管理"),
    "hotkeyNeedsModifier": m33,
    "hotkeyNotSet": MessageLookupByLibrary.simpleMessage("未设置"),
    "hotkeyUnavailable": MessageLookupByLibrary.simpleMessage(
      "未能注册，可能已被其他应用占用",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("小时"),
    "hoursAgo": m34,
    "hoursAgoShort": m35,
    "hue": MessageLookupByLibrary.simpleMessage("色相"),
    "icon": MessageLookupByLibrary.simpleMessage("图标"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("图标记录"),
    "iconSets": MessageLookupByLibrary.simpleMessage("图标集"),
    "iconSetsEmptyTip": MessageLookupByLibrary.simpleMessage(
      "暂无图标集，可在「自定义配置资源 → 图标集」中添加",
    ),
    "iconStyle": MessageLookupByLibrary.simpleMessage("图标样式"),
    "iconStyleFilled": MessageLookupByLibrary.simpleMessage("色块"),
    "iconStyleHidden": MessageLookupByLibrary.simpleMessage("隐藏"),
    "iconStylePlain": MessageLookupByLibrary.simpleMessage("纯图标"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("图标链接"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage("忽略电池优化"),
    "import": MessageLookupByLibrary.simpleMessage("导入"),
    "importConfigInvalid": MessageLookupByLibrary.simpleMessage("此文件不是可导入的配置"),
    "importConfigReplaceTip": MessageLookupByLibrary.simpleMessage(
      "导入会替换此配置现有的策略组、规则和设置",
    ),
    "importFile": MessageLookupByLibrary.simpleMessage("通过文件导入"),
    "importFromLink": MessageLookupByLibrary.simpleMessage("从链接导入"),
    "importUrl": MessageLookupByLibrary.simpleMessage("通过URL导入"),
    "inbound": MessageLookupByLibrary.simpleMessage("入站"),
    "includeInterface": MessageLookupByLibrary.simpleMessage("包含网卡"),
    "includeInterfaceDesc": MessageLookupByLibrary.simpleMessage(
      "只有从包含网卡进入的流量经过虚拟网卡，设置后排除网卡不再生效。",
    ),
    "includeUid": MessageLookupByLibrary.simpleMessage("包含用户 ID"),
    "includeUidDesc": MessageLookupByLibrary.simpleMessage(
      "只有这些用户 ID 的进程产生的流量经过虚拟网卡。",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("长期有效"),
    "init": MessageLookupByLibrary.simpleMessage("初始化"),
    "initFailed": MessageLookupByLibrary.simpleMessage("启动失败"),
    "initFailedTip": MessageLookupByLibrary.simpleMessage(
      "FlClashX 启动时出错，无法继续运行。可以复制错误详情用于反馈；如果问题反复出现，清除数据后通常可以重新启动。",
    ),
    "initiator": MessageLookupByLibrary.simpleMessage("发起方"),
    "initiatorShort": MessageLookupByLibrary.simpleMessage("发起"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage("输入策略组名称"),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage("输入规则内容"),
    "installedAppsPermissionDeniedMessage":
        MessageLookupByLibrary.simpleMessage(
          "读取应用列表权限已被拒绝，无法获取已安装的应用。请前往系统设置手动开启。",
        ),
    "installedAppsPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "当前系统在授权前不会提供已安装的应用列表，授权后即可配置分应用代理。",
    ),
    "installedAppsPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "需要读取应用列表权限",
    ),
    "installedFonts": MessageLookupByLibrary.simpleMessage("已安装字体"),
    "interfaceName": MessageLookupByLibrary.simpleMessage("网卡名称"),
    "interfaceNameDesc": MessageLookupByLibrary.simpleMessage(
      "网卡名称为出站连接使用的网卡。",
    ),
    "interfaceNameMode": MessageLookupByLibrary.simpleMessage("出站网卡"),
    "interfaceNameModeClear": MessageLookupByLibrary.simpleMessage("清空"),
    "interfaceNameModeCustom": MessageLookupByLibrary.simpleMessage("自定义"),
    "interfaceNameModeFollow": MessageLookupByLibrary.simpleMessage("跟随配置"),
    "internet": MessageLookupByLibrary.simpleMessage("互联网"),
    "interval": MessageLookupByLibrary.simpleMessage("间隔"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("内网 IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage("无效备份文件"),
    "invalidCidrContent": MessageLookupByLibrary.simpleMessage(
      "请输入 CIDR 格式的 IP 段，如 192.168.0.0/16",
    ),
    "invalidDscpContent": MessageLookupByLibrary.simpleMessage(
      "DSCP 标记不能超过 63",
    ),
    "invalidHostContent": MessageLookupByLibrary.simpleMessage("请输入域名或 IP 地址"),
    "invalidIconSet": MessageLookupByLibrary.simpleMessage("不是有效的图标集"),
    "invalidLinkTip": MessageLookupByLibrary.simpleMessage("不是有效的订阅链接或代理分享链接"),
    "invalidListenContent": MessageLookupByLibrary.simpleMessage(
      "请输入地址和端口，如 0.0.0.0:1053",
    ),
    "invalidNetworkContent": MessageLookupByLibrary.simpleMessage(
      "仅支持 tcp 或 udp",
    ),
    "invalidPolicy": m36,
    "invalidPortRangeContent": MessageLookupByLibrary.simpleMessage(
      "请输入端口或范围，如 443 或 8000-9000",
    ),
    "invalidProfileQrcode": MessageLookupByLibrary.simpleMessage(
      "该二维码不包含配置文件链接",
    ),
    "invalidProxy": m37,
    "invalidProxyProvider": m38,
    "invalidRangeContent": MessageLookupByLibrary.simpleMessage(
      "请输入数字或范围，如 80 或 8000-9000，多个用 / 分隔",
    ),
    "invalidRuleSet": m39,
    "invalidSubRule": m40,
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP 地址"),
    "ipAsn": MessageLookupByLibrary.simpleMessage("ASN"),
    "ipFlagAbuser": MessageLookupByLibrary.simpleMessage("滥用记录"),
    "ipFlagProxy": MessageLookupByLibrary.simpleMessage("代理"),
    "ipFlagTor": MessageLookupByLibrary.simpleMessage("Tor"),
    "ipFlagVpn": MessageLookupByLibrary.simpleMessage("VPN"),
    "ipFlags": MessageLookupByLibrary.simpleMessage("命中标记"),
    "ipOrganization": MessageLookupByLibrary.simpleMessage("组织"),
    "ipQualityFailed": MessageLookupByLibrary.simpleMessage("类型查询失败"),
    "ipQualityGood": MessageLookupByLibrary.simpleMessage("优"),
    "ipQualityLevel": MessageLookupByLibrary.simpleMessage("等级"),
    "ipQualityNormal": MessageLookupByLibrary.simpleMessage("普通"),
    "ipQualityRetry": MessageLookupByLibrary.simpleMessage("重新查询"),
    "ipQualityRisky": MessageLookupByLibrary.simpleMessage("风险"),
    "ipQualityShort": MessageLookupByLibrary.simpleMessage("质量"),
    "ipQualitySource": MessageLookupByLibrary.simpleMessage("采用来源"),
    "ipQualitySources": MessageLookupByLibrary.simpleMessage("各来源"),
    "ipSourceIpMismatch": MessageLookupByLibrary.simpleMessage("出站 IP 不一致"),
    "ipSourceNoType": MessageLookupByLibrary.simpleMessage("无法判定类型"),
    "ipSourceRateLimited": MessageLookupByLibrary.simpleMessage("限流"),
    "ipType": MessageLookupByLibrary.simpleMessage("类型"),
    "ipTypeBusiness": MessageLookupByLibrary.simpleMessage("商业"),
    "ipTypeHosting": MessageLookupByLibrary.simpleMessage("机房"),
    "ipTypeMobile": MessageLookupByLibrary.simpleMessage("移动网络"),
    "ipTypeResidential": MessageLookupByLibrary.simpleMessage("住宅"),
    "ipTypeUnknown": MessageLookupByLibrary.simpleMessage("类型未知"),
    "ipVersion": MessageLookupByLibrary.simpleMessage("IP 版本"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage("开启 IPv6 后才会接收 IPv6 流量。"),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "开启 IPv6 后，VPN 允许 IPv6 入站。",
    ),
    "ipv6Timeout": MessageLookupByLibrary.simpleMessage("IPv6超时（毫秒）"),
    "itemsCount": m41,
    "ja": MessageLookupByLibrary.simpleMessage("日语"),
    "justNow": MessageLookupByLibrary.simpleMessage("刚刚"),
    "keepAliveIdle": MessageLookupByLibrary.simpleMessage("TCP 保持活动空闲时间"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage("TCP保持活动间隔"),
    "key": MessageLookupByLibrary.simpleMessage("键"),
    "ko": MessageLookupByLibrary.simpleMessage("韩语"),
    "label": MessageLookupByLibrary.simpleMessage("标签"),
    "language": MessageLookupByLibrary.simpleMessage("语言"),
    "large": MessageLookupByLibrary.simpleMessage("大"),
    "lastUpdated": MessageLookupByLibrary.simpleMessage("上次更新"),
    "launchInterrupted": MessageLookupByLibrary.simpleMessage("启动未完成"),
    "launchInterruptedTip": MessageLookupByLibrary.simpleMessage(
      "应用上次在启动过程中意外退出。已跳过本次自动配置，你可以手动启动重试。",
    ),
    "layout": MessageLookupByLibrary.simpleMessage("布局"),
    "light": MessageLookupByLibrary.simpleMessage("浅色"),
    "lineIssueTip": m42,
    "lineWrap": MessageLookupByLibrary.simpleMessage("自动换行"),
    "link": MessageLookupByLibrary.simpleMessage("链接"),
    "linkDesc": MessageLookupByLibrary.simpleMessage("通过订阅链接或代理分享链接获取配置文件"),
    "liquidGlass": MessageLookupByLibrary.simpleMessage("液态玻璃"),
    "list": MessageLookupByLibrary.simpleMessage("列表"),
    "listen": MessageLookupByLibrary.simpleMessage("监听"),
    "listenRoutingMark": MessageLookupByLibrary.simpleMessage("监听路由标记"),
    "listenRoutingMarkDesc": MessageLookupByLibrary.simpleMessage(
      "监听路由标记仅在 Linux 生效。",
    ),
    "liveConnections": MessageLookupByLibrary.simpleMessage("实时连接"),
    "loading": MessageLookupByLibrary.simpleMessage("加载中…"),
    "local": MessageLookupByLibrary.simpleMessage("本地"),
    "localImage": MessageLookupByLibrary.simpleMessage("本地图片"),
    "localNetworkDeniedTip": MessageLookupByLibrary.simpleMessage(
      "本地网络权限被拒绝：已改用 gvisor 栈，局域网无法访问。",
    ),
    "localProxies": MessageLookupByLibrary.simpleMessage("本地代理"),
    "locationPermission": MessageLookupByLibrary.simpleMessage("位置权限"),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "位置权限已被拒绝，无法获取当前 Wi-Fi 名称。请前往系统设置手动开启位置权限。",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "根据系统要求，获取Wi-Fi名称需要您授予位置权限。Android 上请选择“始终允许”，否则应用在后台时无法获取 Wi-Fi 名称。",
    ),
    "locationPermissionGuide": m43,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "需要位置权限",
    ),
    "log": MessageLookupByLibrary.simpleMessage("日志"),
    "logLevel": MessageLookupByLibrary.simpleMessage("日志等级"),
    "logcat": MessageLookupByLibrary.simpleMessage("日志捕获"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage("关闭日志捕获会隐藏日志入口。"),
    "logs": MessageLookupByLibrary.simpleMessage("日志"),
    "logsAndDiagnostics": MessageLookupByLibrary.simpleMessage("日志与诊断"),
    "logsTest": MessageLookupByLibrary.simpleMessage("日志测试"),
    "loopback": MessageLookupByLibrary.simpleMessage("UWP 回环解锁"),
    "loose": MessageLookupByLibrary.simpleMessage("宽松"),
    "managedByProvider": MessageLookupByLibrary.simpleMessage("由提供商管理"),
    "managedByProviderTip": MessageLookupByLibrary.simpleMessage(
      "该值来自订阅。若自行修改，订阅更新将不再改动它。右键或长按该行可交还给提供商。",
    ),
    "managedSettingsHint": MessageLookupByLibrary.simpleMessage(
      "灰显的设置由订阅指定。点按即可自行修改。",
    ),
    "matchCase": MessageLookupByLibrary.simpleMessage("区分大小写"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("匹配来源IP"),
    "matchTarget": MessageLookupByLibrary.simpleMessage("MATCH-TARGET"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("最大失败次数"),
    "maxLengthTip": m44,
    "maximize": MessageLookupByLibrary.simpleMessage("最大化"),
    "memoryAppResident": MessageLookupByLibrary.simpleMessage("常驻内存"),
    "memoryAppShared": MessageLookupByLibrary.simpleMessage("应用及共享"),
    "memoryCoreHeapIdle": MessageLookupByLibrary.simpleMessage("堆内存空闲"),
    "memoryCoreHeapInuse": MessageLookupByLibrary.simpleMessage("堆内存使用中"),
    "memoryCoreNotRunning": MessageLookupByLibrary.simpleMessage("内核未运行"),
    "memoryCoreRuntime": MessageLookupByLibrary.simpleMessage("运行时开销"),
    "memoryCoreStack": MessageLookupByLibrary.simpleMessage("协程栈"),
    "memoryEstimateDesc": MessageLookupByLibrary.simpleMessage(
      "基于进程常驻内存估算，可能与系统显示的数值不同。",
    ),
    "memoryEstimateSharedDesc": MessageLookupByLibrary.simpleMessage(
      "内核与应用运行在同一进程，内核部分按运行时统计估算，其余计入应用及共享内存。",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("内存信息"),
    "memoryInfoDesc": MessageLookupByLibrary.simpleMessage("应用与内核占用的内存"),
    "memoryReleased": MessageLookupByLibrary.simpleMessage("内存已释放"),
    "memoryReleasedSize": m45,
    "menuBarMode": MessageLookupByLibrary.simpleMessage("固定到菜单栏"),
    "menuBarModeDesc": MessageLookupByLibrary.simpleMessage(
      "应用常驻菜单栏：窗口从图标处以弹出面板打开，程序坞中没有图标。缩放按钮同样会固定。",
    ),
    "messageTest": MessageLookupByLibrary.simpleMessage("消息测试"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("这是一条消息。"),
    "minimize": MessageLookupByLibrary.simpleMessage("最小化"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("退出时最小化"),
    "minutes": MessageLookupByLibrary.simpleMessage("分钟"),
    "minutesAgo": m46,
    "minutesAgoShort": m47,
    "mixedPort": MessageLookupByLibrary.simpleMessage("混合端口"),
    "mode": MessageLookupByLibrary.simpleMessage("模式"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("单色"),
    "monthsAgo": m48,
    "monthsAgoShort": m49,
    "more": MessageLookupByLibrary.simpleMessage("更多"),
    "name": MessageLookupByLibrary.simpleMessage("名称"),
    "navigationBarStyle": MessageLookupByLibrary.simpleMessage("底栏"),
    "network": MessageLookupByLibrary.simpleMessage("网络"),
    "networkAccessDeniedError": m50,
    "networkBadResponseError": m51,
    "networkCancelledError": MessageLookupByLibrary.simpleMessage("请求已取消"),
    "networkConnectionError": MessageLookupByLibrary.simpleMessage(
      "无法连接到服务器，请检查网络连接或代理设置",
    ),
    "networkHostLookupError": MessageLookupByLibrary.simpleMessage(
      "无法解析服务器地址，请确认链接正确且 DNS 可用",
    ),
    "networkName": MessageLookupByLibrary.simpleMessage("网络名称"),
    "networkNotFoundError": m52,
    "networkRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "请求过于频繁（HTTP 429），请稍后再试",
    ),
    "networkRequestFailed": m53,
    "networkSecret": MessageLookupByLibrary.simpleMessage("网络密码"),
    "networkServerError": m54,
    "networkSpeed": MessageLookupByLibrary.simpleMessage("网络速度"),
    "networkTakeover": MessageLookupByLibrary.simpleMessage("网络接管"),
    "networkTimeoutError": MessageLookupByLibrary.simpleMessage(
      "请求超时，请检查网络或代理后重试",
    ),
    "networkTlsError": MessageLookupByLibrary.simpleMessage(
      "安全连接失败，服务器证书可能无效，或连接被拦截",
    ),
    "networkType": MessageLookupByLibrary.simpleMessage("网络类型"),
    "nextMatch": MessageLookupByLibrary.simpleMessage("下一个匹配"),
    "no": MessageLookupByLibrary.simpleMessage("否"),
    "noData": MessageLookupByLibrary.simpleMessage("暂无数据"),
    "noInfo": MessageLookupByLibrary.simpleMessage("暂无信息"),
    "noLongerRemind": MessageLookupByLibrary.simpleMessage("不再提示"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("无网络"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("无网络应用"),
    "noResolve": MessageLookupByLibrary.simpleMessage("不解析IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage("不解析主机名"),
    "noSearchResults": MessageLookupByLibrary.simpleMessage("没有匹配的结果"),
    "nodes": MessageLookupByLibrary.simpleMessage("节点"),
    "nonTextProviderFile": MessageLookupByLibrary.simpleMessage("该外部资源不是文本文件"),
    "none": MessageLookupByLibrary.simpleMessage("无"),
    "notRunning": MessageLookupByLibrary.simpleMessage("未运行"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage("当前代理组无法选中"),
    "ntpInterval": MessageLookupByLibrary.simpleMessage("同步间隔（分钟）"),
    "ntpStatusDesc": MessageLookupByLibrary.simpleMessage(
      "开启 NTP 后从 NTP 服务器获取时间，而非系统时钟。",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage("添加一个配置文件后即可开始使用"),
    "nullTip": m55,
    "numberRangeTip": m56,
    "numberTip": m57,
    "obfs": MessageLookupByLibrary.simpleMessage("混淆"),
    "obfsHost": MessageLookupByLibrary.simpleMessage("混淆主机"),
    "obfsMode": MessageLookupByLibrary.simpleMessage("混淆模式"),
    "obfsParam": MessageLookupByLibrary.simpleMessage("混淆参数"),
    "obfsPassword": MessageLookupByLibrary.simpleMessage("混淆密码"),
    "onDemand": MessageLookupByLibrary.simpleMessage("按需运行"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "按需运行会在连上排除的 Wi-Fi 时暂停代理。",
    ),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage("仅统计代理流量"),
    "openLogsFolder": MessageLookupByLibrary.simpleMessage("打开日志文件夹"),
    "optional": MessageLookupByLibrary.simpleMessage("可选"),
    "options": MessageLookupByLibrary.simpleMessage("选项"),
    "originalRepository": MessageLookupByLibrary.simpleMessage("原始仓库"),
    "other": MessageLookupByLibrary.simpleMessage("其他"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("其他贡献者"),
    "outbound": MessageLookupByLibrary.simpleMessage("出站"),
    "outboundExit": MessageLookupByLibrary.simpleMessage("出口"),
    "outboundIp": MessageLookupByLibrary.simpleMessage("出站 IP"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("出站模式"),
    "overrideDestination": MessageLookupByLibrary.simpleMessage("覆盖目标地址"),
    "overrideDestinationDesc": MessageLookupByLibrary.simpleMessage(
      "覆盖目标地址使用嗅探到的域名替换原目标地址发起连接。",
    ),
    "overrideEntries": MessageLookupByLibrary.simpleMessage("覆写项"),
    "parsePureIp": MessageLookupByLibrary.simpleMessage("解析纯IP"),
    "parsePureIpDesc": MessageLookupByLibrary.simpleMessage(
      "解析纯 IP 会嗅探只有 IP 地址的连接。",
    ),
    "password": MessageLookupByLibrary.simpleMessage("密码"),
    "paste": MessageLookupByLibrary.simpleMessage("粘贴"),
    "peers": MessageLookupByLibrary.simpleMessage("初始节点"),
    "pickFromAlbum": MessageLookupByLibrary.simpleMessage("从相册选择"),
    "pinWindow": MessageLookupByLibrary.simpleMessage("窗口置顶"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage("请绑定WebDAV"),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage("请输入脚本名称"),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "请上传有效的二维码",
    ),
    "plugin": MessageLookupByLibrary.simpleMessage("插件"),
    "pluginHost": MessageLookupByLibrary.simpleMessage("插件主机"),
    "pluginMode": MessageLookupByLibrary.simpleMessage("插件模式"),
    "port": MessageLookupByLibrary.simpleMessage("端口"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage("请输入不同的端口"),
    "portHopping": MessageLookupByLibrary.simpleMessage("端口跳跃"),
    "portTip": m58,
    "portValue": m59,
    "ports": MessageLookupByLibrary.simpleMessage("端口"),
    "preSharedKey": MessageLookupByLibrary.simpleMessage("预共享密钥"),
    "prerequisites": MessageLookupByLibrary.simpleMessage("前置条件"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("请按下组合键"),
    "preview": MessageLookupByLibrary.simpleMessage("预览"),
    "previousMatch": MessageLookupByLibrary.simpleMessage("上一个匹配"),
    "privateKey": MessageLookupByLibrary.simpleMessage("私钥"),
    "privateKeyPassphrase": MessageLookupByLibrary.simpleMessage("私钥密码"),
    "process": MessageLookupByLibrary.simpleMessage("进程"),
    "profile": MessageLookupByLibrary.simpleMessage("配置"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入有效间隔时间格式"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入自动更新间隔时间"),
    "profileDaysFigure": m60,
    "profileDaysLeft": m61,
    "profileExpired": MessageLookupByLibrary.simpleMessage("已到期"),
    "profileExpiresIn": m62,
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "配置文件已经修改，是否关闭自动更新？",
    ),
    "profileHoursFigure": m63,
    "profileLeftOfTotal": m64,
    "profileMinutesFigure": m65,
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置名称",
    ),
    "profileNoExpiry": MessageLookupByLibrary.simpleMessage("无期限"),
    "profileSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "仅作用于当前配置，未添加的项使用默认值。",
    ),
    "profileTrafficUnlimited": MessageLookupByLibrary.simpleMessage("不限量"),
    "profileTunSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "仅作用于当前配置，并优先于网络设置中的虚拟网卡覆写项。",
    ),
    "profileTypeCustom": MessageLookupByLibrary.simpleMessage("自定义"),
    "profileTypeFile": MessageLookupByLibrary.simpleMessage("文件"),
    "profileTypeSubscription": MessageLookupByLibrary.simpleMessage("订阅"),
    "profileUntil": m66,
    "profileUpdatedAt": m67,
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入有效配置URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("配置"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("配置排序"),
    "project": MessageLookupByLibrary.simpleMessage("项目"),
    "protocol": MessageLookupByLibrary.simpleMessage("协议"),
    "protocolParam": MessageLookupByLibrary.simpleMessage("协议参数"),
    "protocolVersion": MessageLookupByLibrary.simpleMessage("协议版本"),
    "providerInUse": m68,
    "providerUrlTip": MessageLookupByLibrary.simpleMessage("仅支持远程资源"),
    "providers": MessageLookupByLibrary.simpleMessage("外部资源"),
    "proxies": MessageLookupByLibrary.simpleMessage("代理"),
    "proxiesCount": m69,
    "proxiesProfileLabel": m70,
    "proxiesRemovedTip": m71,
    "proxiesReplacedTip": m72,
    "proxyChains": MessageLookupByLibrary.simpleMessage("代理链"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("策略组"),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage("策略组为空"),
    "proxyGroupInUse": m73,
    "proxyGroupsAfterStart": MessageLookupByLibrary.simpleMessage(
      "启动后在这里显示策略组",
    ),
    "proxyGroupsCount": m74,
    "proxyProviders": MessageLookupByLibrary.simpleMessage("代理集"),
    "proxyType": MessageLookupByLibrary.simpleMessage("代理类型"),
    "pruneCache": MessageLookupByLibrary.simpleMessage("修剪缓存"),
    "publicKey": MessageLookupByLibrary.simpleMessage("公钥"),
    "pureBlack": MessageLookupByLibrary.simpleMessage("纯黑"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("纯黑模式"),
    "qrcode": MessageLookupByLibrary.simpleMessage("二维码"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage("扫描二维码获取配置文件"),
    "quickActions": MessageLookupByLibrary.simpleMessage("快捷操作"),
    "quickEdit": MessageLookupByLibrary.simpleMessage("快速编辑"),
    "recentRequests": MessageLookupByLibrary.simpleMessage("最近请求"),
    "recommendedIcons": MessageLookupByLibrary.simpleMessage("推荐"),
    "recordType": MessageLookupByLibrary.simpleMessage("记录类型"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir端口"),
    "redo": MessageLookupByLibrary.simpleMessage("重做"),
    "regex": MessageLookupByLibrary.simpleMessage("正则"),
    "releaseMemory": MessageLookupByLibrary.simpleMessage("释放内存"),
    "releaseMemoryFailed": MessageLookupByLibrary.simpleMessage("释放内存失败"),
    "remote": MessageLookupByLibrary.simpleMessage("远程"),
    "remoteDestination": MessageLookupByLibrary.simpleMessage("远程目标"),
    "remoteDnsResolve": MessageLookupByLibrary.simpleMessage("远程 DNS 解析"),
    "remove": MessageLookupByLibrary.simpleMessage("移除"),
    "rename": MessageLookupByLibrary.simpleMessage("重命名"),
    "renew": MessageLookupByLibrary.simpleMessage("续费"),
    "replace": MessageLookupByLibrary.simpleMessage("替换"),
    "replaceAll": MessageLookupByLibrary.simpleMessage("全部替换"),
    "request": MessageLookupByLibrary.simpleMessage("请求"),
    "requests": MessageLookupByLibrary.simpleMessage("请求"),
    "requestsAndUpdates": MessageLookupByLibrary.simpleMessage("请求与更新"),
    "required": MessageLookupByLibrary.simpleMessage("必填"),
    "reset": MessageLookupByLibrary.simpleMessage("重置"),
    "resetApp": MessageLookupByLibrary.simpleMessage("重置应用"),
    "resetAppTip": MessageLookupByLibrary.simpleMessage(
      "将删除所有配置文件、设置和应用工作目录，然后应用关闭。继续吗？",
    ),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "当前页面存在更改，确定重置吗？",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage("确定要重置吗？"),
    "resourceUpdateInterval": MessageLookupByLibrary.simpleMessage("自动更新间隔"),
    "resourceUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "自动更新间隔必须大于0",
    ),
    "resources": MessageLookupByLibrary.simpleMessage("资源"),
    "respectRules": MessageLookupByLibrary.simpleMessage("遵守规则"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "遵守规则使 DNS 连接遵守规则，需配置 Proxy Server Nameserver。",
    ),
    "responseCode": MessageLookupByLibrary.simpleMessage("响应码"),
    "restart": MessageLookupByLibrary.simpleMessage("重启"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage("您确定要重启核心吗？"),
    "restore": MessageLookupByLibrary.simpleMessage("恢复"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("恢复所有数据"),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage("仅恢复配置文件"),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("恢复策略"),
    "restoreStrategyCompatible": MessageLookupByLibrary.simpleMessage("兼容"),
    "restoreStrategyOverride": MessageLookupByLibrary.simpleMessage("覆盖"),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage("恢复成功"),
    "result": MessageLookupByLibrary.simpleMessage("结果"),
    "retry": MessageLookupByLibrary.simpleMessage("重试"),
    "returnAllToProvider": MessageLookupByLibrary.simpleMessage("将设置交还给提供商"),
    "returnAllToProviderTip": MessageLookupByLibrary.simpleMessage(
      "您自行修改过的所有设置将重新跟随订阅。",
    ),
    "returnToProvider": MessageLookupByLibrary.simpleMessage("交还给提供商"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("路由地址"),
    "routeExcludeAddress": MessageLookupByLibrary.simpleMessage("排除路由地址"),
    "routingMark": MessageLookupByLibrary.simpleMessage("路由标记"),
    "ru": MessageLookupByLibrary.simpleMessage("俄语"),
    "rule": MessageLookupByLibrary.simpleMessage("规则"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 AND"),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage("匹配完整域名"),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "匹配域名关键字",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用域名正则表达式匹配",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配域名后缀",
    ),
    "ruleActionDomainWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "通配符匹配，仅支持*和?通配符",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "匹配DSCP标记（仅限 tproxy udp 入站）",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage("匹配请求目标端口范围"),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 所属国家代码"),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 Geosite 内的域名",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage("匹配入站名称"),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage("匹配入站端口"),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage("匹配入站类型"),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "匹配入站用户名，支持使用 / 分隔多个用户名",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 所属 ASN"),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "匹配 IP 地址范围，IP-CIDR6 只是一个别名",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage("匹配 IP 地址范围"),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 IP 后缀范围",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage("匹配所有请求，无需条件"),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage("匹配TCP或者UDP"),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 NOT"),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("逻辑规则 OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程匹配，在Android平台可以匹配包名",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程名称正则表达式匹配，在Android平台可以匹配包名",
    ),
    "ruleActionProcessNameWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程名称通配符匹配，仅支持*和?通配符",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "使用完整进程路径匹配",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程路径正则表达式匹配",
    ),
    "ruleActionProcessPathWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "使用进程路径通配符匹配，仅支持*和?通配符",
    ),
    "ruleActionRematchNameDesc": MessageLookupByLibrary.simpleMessage(
      "匹配重匹配名称，多个名称用/分隔",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "引用规则集合，需配置rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 所属国家代码",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 所属 ASN",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 地址范围",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "匹配来源 IP 后缀范围",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage("匹配请求来源端口范围"),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "匹配至子规则，需要注意括号的使用",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "匹配 Linux USER ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("规则为空"),
    "ruleListInvalid": MessageLookupByLibrary.simpleMessage(
      "规则必须是 YAML 列表，每项一条规则，例如 - DOMAIN,example.com,DIRECT",
    ),
    "rulePresetBittorrentDirect": MessageLookupByLibrary.simpleMessage(
      "BT 下载直连",
    ),
    "rulePresetBlockDot": MessageLookupByLibrary.simpleMessage(
      "屏蔽 DNS over TLS",
    ),
    "rulePresetBlockLoopback": MessageLookupByLibrary.simpleMessage("防止代理回环"),
    "rulePresetBlockQuic": MessageLookupByLibrary.simpleMessage("屏蔽 QUIC"),
    "rulePresetBlockStun": MessageLookupByLibrary.simpleMessage("屏蔽 STUN"),
    "rulePresetLanDirect": MessageLookupByLibrary.simpleMessage("局域网直连"),
    "rulePresetSystemServicesDirect": MessageLookupByLibrary.simpleMessage(
      "Apple 与 Microsoft 直连",
    ),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("规则集"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("规则集"),
    "ruleSetEmptyTip": MessageLookupByLibrary.simpleMessage("规则集中没有可用的条目"),
    "ruleSetInvalidTip": MessageLookupByLibrary.simpleMessage("无法读取该 mrs 文件"),
    "ruleSetMixedTip": MessageLookupByLibrary.simpleMessage(
      "规则集同时包含域名和 IP 段，无法判断类型",
    ),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("规则目标"),
    "ruleTextInvalid": MessageLookupByLibrary.simpleMessage(
      "规则必须以受支持的类型开头，例如 DOMAIN,example.com,DIRECT",
    ),
    "rules": MessageLookupByLibrary.simpleMessage("规则"),
    "rulesCount": m75,
    "runTime": MessageLookupByLibrary.simpleMessage("运行时长"),
    "running": MessageLookupByLibrary.simpleMessage("运行中"),
    "runtimeConfig": MessageLookupByLibrary.simpleMessage("运行时配置"),
    "safeMode": MessageLookupByLibrary.simpleMessage("安全模式"),
    "safeModeAppTitle": m76,
    "saturation": MessageLookupByLibrary.simpleMessage("饱和度"),
    "save": MessageLookupByLibrary.simpleMessage("保存"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("是否保存更改？"),
    "script": MessageLookupByLibrary.simpleMessage("脚本"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage("脚本模式，使用扩展脚本改写整个配置"),
    "scrollToSelected": MessageLookupByLibrary.simpleMessage("滚动到已选"),
    "search": MessageLookupByLibrary.simpleMessage("搜索"),
    "seconds": MessageLookupByLibrary.simpleMessage("秒"),
    "secondsCount": m77,
    "secretKey": MessageLookupByLibrary.simpleMessage("密钥"),
    "sectionsInEffect": m78,
    "selectAll": MessageLookupByLibrary.simpleMessage("全选"),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage("请选择规则集"),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage("请选择分流策略"),
    "selected": MessageLookupByLibrary.simpleMessage("已选择"),
    "sendDeviceHeaders": MessageLookupByLibrary.simpleMessage("发送 HWID"),
    "server": MessageLookupByLibrary.simpleMessage("服务器"),
    "serviceAbnormalCount": m79,
    "serviceAllAvailable": MessageLookupByLibrary.simpleMessage("全部可用"),
    "serviceAvailable": MessageLookupByLibrary.simpleMessage("可用"),
    "serviceBlocked": MessageLookupByLibrary.simpleMessage("已被封禁"),
    "serviceCheck": MessageLookupByLibrary.simpleMessage("检测"),
    "serviceCheckAll": MessageLookupByLibrary.simpleMessage("全部检测"),
    "serviceCheckedAt": m80,
    "serviceComingSoon": MessageLookupByLibrary.simpleMessage("即将上线"),
    "serviceDisallowedIsp": MessageLookupByLibrary.simpleMessage("不允许的 ISP"),
    "serviceFailed": MessageLookupByLibrary.simpleMessage("检测失败"),
    "serviceManage": MessageLookupByLibrary.simpleMessage("管理服务"),
    "serviceOriginalsOnly": MessageLookupByLibrary.simpleMessage("仅限自制内容"),
    "servicePending": MessageLookupByLibrary.simpleMessage("待检测"),
    "serviceRestricted": MessageLookupByLibrary.simpleMessage("访问受限"),
    "serviceShownOnDashboard": MessageLookupByLibrary.simpleMessage("显示在仪表盘"),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("服务状态"),
    "serviceUnavailable": MessageLookupByLibrary.simpleMessage("不可用"),
    "serviceUnsupportedRegion": MessageLookupByLibrary.simpleMessage("地区不支持"),
    "settingEntries": MessageLookupByLibrary.simpleMessage("设置项"),
    "settings": MessageLookupByLibrary.simpleMessage("设置"),
    "settingsCount": m81,
    "shareLinkUnreadable": m82,
    "shareLinksInvalid": MessageLookupByLibrary.simpleMessage("无法从链接中读取代理"),
    "show": MessageLookupByLibrary.simpleMessage("显示"),
    "showLess": MessageLookupByLibrary.simpleMessage("收起"),
    "showMore": MessageLookupByLibrary.simpleMessage("展开"),
    "showNotificationStopAction": MessageLookupByLibrary.simpleMessage(
      "通知栏显示停止按钮",
    ),
    "showPassword": MessageLookupByLibrary.simpleMessage("显示密码"),
    "sidebarBlur": MessageLookupByLibrary.simpleMessage("侧边栏背景模糊"),
    "sidebarBlurDesc": MessageLookupByLibrary.simpleMessage("侧边栏透出窗口后方模糊的桌面"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("静默启动"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage("静默启动时不显示窗口。"),
    "singleAdd": MessageLookupByLibrary.simpleMessage("单条添加"),
    "singleImport": MessageLookupByLibrary.simpleMessage("单条导入"),
    "singleShareLinkOnly": MessageLookupByLibrary.simpleMessage(
      "这里只能填写一条链接，多条请在列表的快速编辑中填写",
    ),
    "singleValueTip": m83,
    "size": MessageLookupByLibrary.simpleMessage("尺寸"),
    "skipCertVerify": MessageLookupByLibrary.simpleMessage("跳过证书验证"),
    "skipDomain": MessageLookupByLibrary.simpleMessage("跳过域名"),
    "skipDomainDesc": MessageLookupByLibrary.simpleMessage("嗅探到跳过域名中的域名时不予采用。"),
    "skipDstAddress": MessageLookupByLibrary.simpleMessage("跳过目标地址"),
    "skipSrcAddress": MessageLookupByLibrary.simpleMessage("跳过来源地址"),
    "slide": MessageLookupByLibrary.simpleMessage("滑动"),
    "sliders": MessageLookupByLibrary.simpleMessage("滑块"),
    "sniffProtocols": MessageLookupByLibrary.simpleMessage("协议"),
    "sniffer": MessageLookupByLibrary.simpleMessage("域名嗅探"),
    "snifferStatusDesc": MessageLookupByLibrary.simpleMessage(
      "域名嗅探从 TLS、HTTP、QUIC 流量中识别域名，供规则匹配。",
    ),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks端口"),
    "softStyle": MessageLookupByLibrary.simpleMessage("柔和"),
    "sort": MessageLookupByLibrary.simpleMessage("排序"),
    "source": MessageLookupByLibrary.simpleMessage("来源"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("源IP"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("特殊代理"),
    "specialRules": MessageLookupByLibrary.simpleMessage("特殊规则"),
    "spectrum": MessageLookupByLibrary.simpleMessage("光谱"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("网速统计"),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("分流策略"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage("分流策略不能为空"),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs为空"),
    "stackMode": MessageLookupByLibrary.simpleMessage("栈模式"),
    "stackTrace": MessageLookupByLibrary.simpleMessage("堆栈信息"),
    "standard": MessageLookupByLibrary.simpleMessage("标准"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "标准模式，在配置的基础上附加规则",
    ),
    "start": MessageLookupByLibrary.simpleMessage("启动"),
    "startFromScratch": MessageLookupByLibrary.simpleMessage("从零开始"),
    "startVpn": MessageLookupByLibrary.simpleMessage("正在启动VPN…"),
    "startupAndBackground": MessageLookupByLibrary.simpleMessage("启动与后台"),
    "status": MessageLookupByLibrary.simpleMessage("状态"),
    "statusDesc": MessageLookupByLibrary.simpleMessage("关闭 DNS 后将使用系统 DNS。"),
    "stop": MessageLookupByLibrary.simpleMessage("暂停"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("正在停止VPN…"),
    "strategy": MessageLookupByLibrary.simpleMessage("策略"),
    "strictRoute": MessageLookupByLibrary.simpleMessage("严格路由"),
    "strictRouteDesc": MessageLookupByLibrary.simpleMessage(
      "严格路由防止 DNS 等流量绕过虚拟网卡，关闭 IPv6 时会阻断本机的 IPv6 连接。",
    ),
    "style": MessageLookupByLibrary.simpleMessage("风格"),
    "submit": MessageLookupByLibrary.simpleMessage("提交"),
    "subscriptionExpired": MessageLookupByLibrary.simpleMessage("您的订阅已到期"),
    "subscriptionExpiresInDays": m84,
    "subscriptionExpiresSoon": MessageLookupByLibrary.simpleMessage("订阅即将到期"),
    "subscriptionExpiresToday": MessageLookupByLibrary.simpleMessage(
      "您的订阅今天到期",
    ),
    "subscriptionInfo": MessageLookupByLibrary.simpleMessage("订阅信息"),
    "sudoPasswordTitle": MessageLookupByLibrary.simpleMessage("输入 sudo 密码"),
    "support": MessageLookupByLibrary.simpleMessage("支持"),
    "suspended": MessageLookupByLibrary.simpleMessage("挂起中…"),
    "switchProfile": MessageLookupByLibrary.simpleMessage("切换配置"),
    "sync": MessageLookupByLibrary.simpleMessage("同步"),
    "system": MessageLookupByLibrary.simpleMessage("系统"),
    "systemApp": MessageLookupByLibrary.simpleMessage("系统应用"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "tab": MessageLookupByLibrary.simpleMessage("标签页"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("选项卡动画"),
    "takeOver": MessageLookupByLibrary.simpleMessage("修改"),
    "tapIconToRetry": MessageLookupByLibrary.simpleMessage("点击图标重试"),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("点击授权"),
    "target": MessageLookupByLibrary.simpleMessage("目标"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP并发"),
    "testInterval": MessageLookupByLibrary.simpleMessage("测试间隔"),
    "testUrl": MessageLookupByLibrary.simpleMessage("测速链接"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("使用时测试"),
    "textScale": MessageLookupByLibrary.simpleMessage("文本缩放"),
    "textScalePreview": MessageLookupByLibrary.simpleMessage("应用内的文字将以这个大小显示"),
    "thanks": MessageLookupByLibrary.simpleMessage("感谢贡献"),
    "theme": MessageLookupByLibrary.simpleMessage("主题"),
    "themeColor": MessageLookupByLibrary.simpleMessage("主题色彩"),
    "themeMode": MessageLookupByLibrary.simpleMessage("外观"),
    "themeStyle": MessageLookupByLibrary.simpleMessage("主题模式"),
    "themeStyleDesc": MessageLookupByLibrary.simpleMessage(
      "增强版在主页显示服务标志、套餐、服务器和连接按钮，取代小部件网格。",
    ),
    "themeStyleEnhanced": MessageLookupByLibrary.simpleMessage("增强版"),
    "themeStyleOriginal": MessageLookupByLibrary.simpleMessage("原版"),
    "tight": MessageLookupByLibrary.simpleMessage("紧凑"),
    "time": MessageLookupByLibrary.simpleMessage("时间"),
    "timeout": MessageLookupByLibrary.simpleMessage("超时"),
    "tintedStyle": MessageLookupByLibrary.simpleMessage("氛围"),
    "tip": MessageLookupByLibrary.simpleMessage("提示"),
    "toggle": MessageLookupByLibrary.simpleMessage("切换"),
    "tolerance": MessageLookupByLibrary.simpleMessage("容差"),
    "tools": MessageLookupByLibrary.simpleMessage("设置"),
    "torch": MessageLookupByLibrary.simpleMessage("手电筒"),
    "total": MessageLookupByLibrary.simpleMessage("总计"),
    "totalDownload": MessageLookupByLibrary.simpleMessage("下载总量"),
    "totalTraffic": MessageLookupByLibrary.simpleMessage("总流量"),
    "totalUpload": MessageLookupByLibrary.simpleMessage("上传总量"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy端口"),
    "traffic": MessageLookupByLibrary.simpleMessage("流量"),
    "trafficPeak": m85,
    "trafficTotal": m86,
    "trafficUsage": MessageLookupByLibrary.simpleMessage("流量统计"),
    "transport": MessageLookupByLibrary.simpleMessage("传输协议"),
    "tun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "tunAuthorizationFailed": MessageLookupByLibrary.simpleMessage(
      "虚拟网卡授权失败，已关闭。",
    ),
    "tunDesc": MessageLookupByLibrary.simpleMessage("虚拟网卡仅在管理员模式生效。"),
    "tunOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "添加的项会覆写所有配置的虚拟网卡设置，未添加的项沿用配置自身的设置。自定义配置自己添加的项优先。",
    ),
    "turnOff": MessageLookupByLibrary.simpleMessage("关闭"),
    "turnOn": MessageLookupByLibrary.simpleMessage("开启"),
    "udpRelayMode": MessageLookupByLibrary.simpleMessage("UDP 中继模式"),
    "udpTimeout": MessageLookupByLibrary.simpleMessage("UDP 超时"),
    "udpTimeoutDesc": MessageLookupByLibrary.simpleMessage(
      "UDP 超时以秒为单位，仅在 gvisor、system 和 mixed 栈生效。",
    ),
    "ultra": MessageLookupByLibrary.simpleMessage("极致"),
    "undo": MessageLookupByLibrary.simpleMessage("撤销"),
    "unfoldAllGroups": MessageLookupByLibrary.simpleMessage("展开所有分组"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("统一延迟"),
    "unknown": MessageLookupByLibrary.simpleMessage("未知"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage("未知网络错误"),
    "unmaximize": MessageLookupByLibrary.simpleMessage("向下还原"),
    "unnamed": MessageLookupByLibrary.simpleMessage("未命名"),
    "unpinWindow": MessageLookupByLibrary.simpleMessage("取消置顶"),
    "update": MessageLookupByLibrary.simpleMessage("更新"),
    "upload": MessageLookupByLibrary.simpleMessage("上传"),
    "uploadBandwidth": MessageLookupByLibrary.simpleMessage("上行带宽"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlTip": m87,
    "useHosts": MessageLookupByLibrary.simpleMessage("使用Hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("使用系统Hosts"),
    "usedShort": MessageLookupByLibrary.simpleMessage("已用"),
    "usedTraffic": MessageLookupByLibrary.simpleMessage("已用流量"),
    "username": MessageLookupByLibrary.simpleMessage("用户名"),
    "value": MessageLookupByLibrary.simpleMessage("值"),
    "view": MessageLookupByLibrary.simpleMessage("查看"),
    "virtualIpv4": MessageLookupByLibrary.simpleMessage("虚拟 IPv4"),
    "vividStyle": MessageLookupByLibrary.simpleMessage("鲜明"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "检测到VPN相关配置改动",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "VPN 通过 VpnService 自动路由系统所有流量。",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage("WebDAV配置"),
    "website": MessageLookupByLibrary.simpleMessage("网站"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("白名单模式"),
    "writeToSystem": MessageLookupByLibrary.simpleMessage("写入系统"),
    "writeToSystemDesc": MessageLookupByLibrary.simpleMessage(
      "写入系统会同时设置系统时钟，Android 上不生效。",
    ),
    "yearsAgo": m88,
    "yearsAgoShort": m89,
    "yes": MessageLookupByLibrary.simpleMessage("是"),
    "zhCN": MessageLookupByLibrary.simpleMessage("中文简体"),
  };
}
