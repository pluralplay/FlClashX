import 'dart:math' as math;
import 'dart:math' show max, min;
import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/widgets/start_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Design tokens (Cosmic Space theme) ────────────────────────────────────────
const _kAccent = Color(0xFF7B45E8);      // nebula purple
const _kAccent2 = Color(0xFF4FECF7);     // stellar cyan
const _kGreen = Color(0xFF00FFB0);       // neon mint
const _kRed = Color(0xFFFF4D6A);
const _kAmber = Color(0xFFF5A623);
const _kBgDark = Color(0xFF05050E);      // deep space
const _kCard = Color(0xCC0A0A1F);        // deep space card
const _kCardBorder = Color(0x286450FF);  // faint purple border
const _kText2 = Color(0x8CDCE8FF);
const _kText3 = Color(0x4DDCE8FF);

// ── Dashboard ──────────────────────────────────────────────────────────────────

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStart = ref.watch(runTimeProvider.select((t) => t != null));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Starfield background
          if (isDark) const _Starfield(),
          // Nebula orbs
          if (isDark) ...[
            _Orb(
              color: _kAccent,
              size: 420,
              alignment: const Alignment(1.3, -1.1),
            ),
            _Orb(
              color: isStart ? _kGreen : const Color(0xFF0A0A2E),
              size: 380,
              alignment: const Alignment(-1.3, 1.2),
            ),
            _Orb(
              color: _kAccent2,
              size: 250,
              alignment: const Alignment(0.0, -0.6),
            ),
          ],
          // Content
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      // ── Top bar ──────────────────────────────────────────
                      _TopBar(isDark: isDark),
                      const SizedBox(height: 16),
                      // ── Connection card ───────────────────────────────────
                      _ConnectionCard(isStart: isStart, isDark: isDark),
                      const SizedBox(height: 12),
                      // ── Traffic chart ────────────────────────────────────
                      _TrafficCard(isDark: isDark),
                      const SizedBox(height: 12),
                      // ── Proxy groups ─────────────────────────────────────
                      _ProxyGroupsCard(isDark: isDark),
                      const SizedBox(height: 12),
                      // ── Bypass shortcut ──────────────────────────────────
                      _BypassShortcutCard(isDark: isDark),
                    ],
                  ),
                ),
                // Start/Stop button
                const StartButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Starfield ──────────────────────────────────────────────────────────────────

class _Starfield extends StatelessWidget {
  const _Starfield();

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: _StarPainter(seed: 42),
      );
}

class _StarPainter extends CustomPainter {
  _StarPainter({required this.seed});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 120; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = rng.nextDouble() * 1.2 + 0.3;
      final opacity = rng.nextDouble() * 0.5 + 0.1;
      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}

// ── Background orb ─────────────────────────────────────────────────────────────

class _Orb extends StatelessWidget {
  const _Orb({
    required this.color,
    required this.size,
    required this.alignment,
  });

  final Color color;
  final double size;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.08),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

Future<void> _clipboardImport() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final url = data?.text?.trim();
  if (url != null && url.isNotEmpty) {
    globalState.appController.addProfileFormURL(url);
  }
}

// ── Top bar ─────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/icon.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'FlowXray',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const Spacer(),
          _IconBtn(
            icon: Icons.content_paste_go_outlined,
            isDark: isDark,
            onTap: _clipboardImport,
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.settings_outlined,
            isDark: isDark,
            onTap: () => globalState.appController.toPage(PageLabel.tools),
          ),
        ],
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _kCard,
            border: Border.all(color: _kCardBorder),
          ),
          child: Icon(icon,
              size: 18,
              color: isDark ? _kText2 : const Color(0x8C0A0A1A)),
        ),
      );
}

// ── Connection card ────────────────────────────────────────────────────────────

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({required this.isStart, required this.isDark});
  final bool isStart;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runTime = ref.watch(runTimeProvider);
    final localIp = ref.watch(localIpProvider);
    final latestTraffic = ref.watch(
      trafficsProvider.select((list) => list.length > 0 ? list[list.length - 1] : null),
    );

    final borderColor = isStart
        ? _kGreen.withValues(alpha: 0.25)
        : _kCardBorder;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: _kCard,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'СТАТУС',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: _kText3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _StatusDot(isActive: isStart),
                            const SizedBox(width: 8),
                            Text(
                              isStart ? 'Подключён' : 'Отключён',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isStart
                              ? (localIp != null
                                  ? 'IP: $localIp'
                                  : runTime != null
                                      ? utils.getTimeText(runTime)
                                      : '')
                              : 'IP: —',
                          style: const TextStyle(
                              fontSize: 12,
                              color: _kText3,
                              fontFamily: 'JetBrainsMono'),
                        ),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 18),
                // Stats row
                Row(
                  children: [
                    _StatBox(
                      label: '↓ Приём',
                      value: latestTraffic?.down.show ?? '—',
                    ),
                    const SizedBox(width: 10),
                    _StatBox(
                      label: '↑ Отдача',
                      value: latestTraffic?.up.show ?? '—',
                    ),
                    const SizedBox(width: 10),
                    Consumer(builder: (_, ref, __) {
                      final total = ref.watch(totalTrafficProvider);
                      return _StatBox(
                        label: 'Всего ↓',
                        value: total.down.show,
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 14),
                // Profile/proxy display
                _ProxySelector(isDark: isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.isActive});
  final bool isActive;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _kText3,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kGreen,
          boxShadow: [
            BoxShadow(
              color: _kGreen.withValues(
                  alpha: 0.3 + 0.4 * _anim.value),
              blurRadius: 6 + 8 * _anim.value,
              spreadRadius: _anim.value * 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontSize: 10,
                    color: _kText3,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'JetBrainsMono',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
}

class _ProxySelector extends ConsumerWidget {
  const _ProxySelector({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final groups = ref.watch(currentGroupsStateProvider).value;
    final firstGroup = groups.isNotEmpty ? groups.first : null;
    final selectedMap = ref.watch(selectedMapProvider);
    final selected = firstGroup != null
        ? (selectedMap[firstGroup.name] ?? firstGroup.now ?? '—')
        : '—';

    return GestureDetector(
      onTap: () => globalState.appController.toPage(PageLabel.proxies),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.dns_outlined, size: 20, color: _kText3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.label ?? profile?.id ?? 'Профиль',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (firstGroup != null)
                    Text(
                      selected,
                      style: TextStyle(
                        fontSize: 11,
                        color: _kGreen,
                        fontFamily: 'JetBrainsMono',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _kText3, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Traffic chart card ─────────────────────────────────────────────────────────

class _TrafficCard extends ConsumerWidget {
  const _TrafficCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffics = ref.watch(trafficsProvider);
    final total = ref.watch(totalTrafficProvider);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _kCard,
        border: Border.all(color: _kCardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Трафик сессии',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? _kText2 : const Color(0x8C0A0A1A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '↓ ${total.down.show}  ↑ ${total.up.show}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: _kText3,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: _TrafficBars(traffics: traffics),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Legend(color: _kAccent, label: 'Загрузка'),
                    const SizedBox(width: 12),
                    _Legend(
                        color: _kAccent.withValues(alpha: 0.35),
                        label: 'Отдача'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrafficBars extends StatelessWidget {
  const _TrafficBars({required this.traffics});
  final FixedList<Traffic> traffics;

  @override
  Widget build(BuildContext context) {
    const barCount = 20;
    final list = traffics.list;
    // pad on the left with empty bars if less than barCount
    final padded = <Traffic?>[
      ...List.filled(math.max(0, barCount - list.length), null),
      ...list.take(barCount),
    ];
    final maxDown = list.isEmpty
        ? 1
        : list.map((t) => t.down.value).reduce(max).clamp(1, double.infinity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(padded.length, (i) {
        final t = padded[i];
        final isLast = i == padded.length - 1;
        final heightFrac =
            t == null ? 0.0 : (t.down.value / maxDown).clamp(0.0, 1.0);
        final upFrac =
            t == null ? 0.0 : (t.up.value / maxDown).clamp(0.0, 1.0);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Download bar
                Flexible(
                  flex: ((heightFrac * 48).toInt()).clamp(1, 48),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3)),
                      color: isLast
                          ? _kAccent
                          : _kAccent.withValues(alpha: 0.28),
                    ),
                    width: double.infinity,
                  ),
                ),
                // Upload bar overlay (smaller, different shade)
                if (upFrac > 0)
                  Flexible(
                    flex: ((upFrac * 20).toInt()).clamp(0, 20),
                    child: Container(
                      color: _kAccent2.withValues(alpha: 0.4),
                      width: double.infinity,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: _kText3)),
        ],
      );
}

// ── Proxy groups card ──────────────────────────────────────────────────────────

class _ProxyGroupsCard extends ConsumerWidget {
  const _ProxyGroupsCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(currentGroupsStateProvider).value;
    final selectedMap = ref.watch(selectedMapProvider);

    if (groups.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _kCard,
        border: Border.all(color: _kCardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  children: [
                    Text(
                      'ГРУППЫ ПРОКСИ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: _kText3,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => globalState.appController
                          .toPage(PageLabel.proxies),
                      child: const Text(
                        'Все',
                        style: TextStyle(
                            fontSize: 12,
                            color: _kAccent2,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              ...groups.take(4).toList().asMap().entries.map((entry) {
                final i = entry.key;
                final group = entry.value;
                final selected = selectedMap[group.name] ?? group.now ?? '—';
                final isLast = i == min(groups.length, 4) - 1;

                return GestureDetector(
                  onTap: () =>
                      globalState.appController.toPage(PageLabel.proxies),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : Border(
                              bottom: BorderSide(
                                  color: _kCardBorder, width: 0.5),
                            ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      isDark ? Colors.white : Colors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                selected,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _kText3,
                                  fontFamily: 'JetBrainsMono',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: _kAccent.withValues(alpha: 0.12),
                          ),
                          child: Text(
                            group.type.value,
                            style: const TextStyle(
                                fontSize: 10,
                                color: _kAccent2,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bypass shortcut card ───────────────────────────────────────────────────────

class _BypassShortcutCard extends StatelessWidget {
  const _BypassShortcutCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () =>
            globalState.appController.toPage(PageLabel.bypass),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: _kCard,
            border: Border.all(color: _kCardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _kAccent.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: _kAccent2, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bypass — Исключения',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Text(
                      'Приложения с автоотключением VPN',
                      style:
                          TextStyle(fontSize: 11, color: _kText3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _kText3, size: 20),
            ],
          ),
        ),
      );
}
