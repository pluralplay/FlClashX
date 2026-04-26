import 'dart:io';

import 'package:flclashx/models/models.dart';
import 'package:flclashx/plugins/app.dart';
import 'package:flclashx/plugins/bypass.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBypassKey = 'flowxray_bypass_packages';

// Cosmic theme tokens
const _accent = Color(0xFF7B45E8);
const _green = Color(0xFF00FFB0);
const _bg3 = Color(0xFF0A0A1F);
const _cardBorder = Color(0x286450FF);
const _text2 = Color(0x8CDCE8FF);
const _text3 = Color(0x4DDCE8FF);

class BypassView extends StatefulWidget {
  const BypassView({super.key});

  @override
  State<BypassView> createState() => _BypassViewState();
}

class _BypassViewState extends State<BypassView> {
  List<Package> _allPackages = [];
  Set<String> _bypassPackages = {};
  bool _loading = true;
  bool _hasPermission = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!Platform.isAndroid) {
      setState(() => _loading = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kBypassKey) ?? [];
    final hasPermission = await ForegroundMonitor.hasPermission();
    final packages = await app?.getPackages() ?? [];
    final userApps = packages
        .where((p) => !p.system && p.internet)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    if (!mounted) return;
    setState(() {
      _bypassPackages = saved.toSet();
      _allPackages = userApps;
      _hasPermission = hasPermission;
      _loading = false;
    });
    await ForegroundMonitor.setBypassPackages(saved);
    if (saved.isNotEmpty && hasPermission) {
      await ForegroundMonitor.startMonitor();
    }
  }

  Future<void> _toggle(String packageName) async {
    final updated = Set<String>.from(_bypassPackages);
    if (updated.contains(packageName)) {
      updated.remove(packageName);
    } else {
      updated.add(packageName);
    }
    setState(() => _bypassPackages = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBypassKey, updated.toList());
    await ForegroundMonitor.setBypassPackages(updated.toList());
    if (updated.isNotEmpty && _hasPermission) {
      await ForegroundMonitor.startMonitor();
    } else if (updated.isEmpty) {
      await ForegroundMonitor.stopMonitor();
    }
  }

  Future<void> _requestPermission() async {
    await ForegroundMonitor.requestPermission();
    await Future.delayed(const Duration(seconds: 1));
    final has = await ForegroundMonitor.hasPermission();
    if (!mounted) return;
    setState(() => _hasPermission = has);
    if (has && _bypassPackages.isNotEmpty) {
      await ForegroundMonitor.startMonitor();
    }
  }

  List<Package> get _filtered {
    if (_query.isEmpty) return _allPackages;
    final q = _query.toLowerCase();
    return _allPackages
        .where((p) =>
            p.label.toLowerCase().contains(q) ||
            p.packageName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF05050E) : const Color(0xFFF5F5F7);
    final cardColor =
        isDark ? const Color(0x0AFFFFFF) : const Color(0xD9FFFFFF);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _bypassPackages.isNotEmpty && _hasPermission
                            ? _green
                            : _text3,
                        boxShadow:
                            _bypassPackages.isNotEmpty && _hasPermission
                                ? [
                                    BoxShadow(
                                        color:
                                            _green.withValues(alpha: 0.5),
                                        blurRadius: 8)
                                  ]
                                : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Bypass — Исключения',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'При открытии выбранного приложения VPN автоматически отключается',
                  style: TextStyle(fontSize: 13, color: _text2),
                ),
              ],
            ),
          ),

          if (!_hasPermission && Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _PermissionBanner(onTap: _requestPermission),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black),
                decoration: const InputDecoration(
                  hintText: 'Поиск приложений...',
                  hintStyle: TextStyle(color: _text3),
                  prefixIcon: Icon(Icons.search, color: _text3, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _accent))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('Приложения не найдены',
                            style: TextStyle(color: _text2)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final pkg = _filtered[i];
                          return _AppBypassTile(
                            pkg: pkg,
                            enabled: _bypassPackages.contains(pkg.packageName),
                            isDark: isDark,
                            onToggle: () => _toggle(pkg.packageName),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0x1AF5A623),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x33F5A623)),
          ),
          child: Row(
            children: const [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFF5A623), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Требуется доступ к статистике использования — нажмите для настройки',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFF5A623),
                      fontWeight: FontWeight.w500),
                ),
              ),
              Icon(Icons.chevron_right, color: Color(0x80F5A623), size: 18),
            ],
          ),
        ),
      );
}

class _AppBypassTile extends StatefulWidget {
  const _AppBypassTile({
    required this.pkg,
    required this.enabled,
    required this.isDark,
    required this.onToggle,
  });

  final Package pkg;
  final bool enabled;
  final bool isDark;
  final VoidCallback onToggle;

  @override
  State<_AppBypassTile> createState() => _AppBypassTileState();
}

class _AppBypassTileState extends State<_AppBypassTile> {
  ImageProvider? _icon;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  Future<void> _loadIcon() async {
    if (!Platform.isAndroid) return;
    final icon = await app?.getPackageIcon(widget.pkg.packageName);
    if (icon != null && mounted) setState(() => _icon = icon);
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = widget.isDark
        ? const Color(0x0AFFFFFF)
        : const Color(0xD9FFFFFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.enabled ? const Color(0x14F0F0F8) : cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.enabled ? _accent.withValues(alpha: 0.3) : _cardBorder,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _icon != null
              ? Image(image: _icon!, width: 40, height: 40)
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _bg3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.apps, color: _text3, size: 20),
                ),
        ),
        title: Text(
          widget.pkg.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
        subtitle: Text(
          widget.enabled ? 'VPN выключен при запуске' : 'Через VPN',
          style: TextStyle(
              fontSize: 11,
              color: widget.enabled ? _green : _text3),
        ),
        trailing: GestureDetector(
          onTap: widget.onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 48,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color:
                  widget.enabled ? _accent : const Color(0xFF22222F),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  left: widget.enabled ? 24 : 3,
                  top: 3,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Color(0x33000000), blurRadius: 4)
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
