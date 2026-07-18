import 'dart:ui';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../data/app_store.dart';
import '../services/services.dart';
import 'day_sheet.dart';
import 'paywall.dart';
import 'rotation_sheet.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late int _year;
  late int _month;
  String? _brush;

  @override
  void initState() {
    super.initState();
    final t = appStore.today;
    _year = t.year;
    _month = t.month;
  }

  void _prevMonth() => setState(() {
        _month--;
        if (_month < 1) {
          _month = 12;
          _year--;
        }
      });

  void _nextMonth() => setState(() {
        _month++;
        if (_month > 12) {
          _month = 1;
          _year++;
        }
      });

  void _goToday() => setState(() {
        final t = appStore.today;
        _year = t.year;
        _month = t.month;
      });

  void _onTapDay(String key, bool locked) {
    if (locked) {
      showPaywall(context, reason: PaywallReason.locked);
      return;
    }
    if (_brush != null) {
      final plan = appStore.dayPlans[key];
      if (plan != null && plan.presetId == _brush && !plan.hasOverride) {
        appStore.clearDay(key);
      } else {
        appStore.assignPreset(key, _brush!);
      }
    } else {
      showDaySheet(context, key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appStore,
      builder: (context, _) {
        return Column(
          children: [
            _header(context),
            _nextAlarmBanner(context),
            _monthBar(context),
            _weekdayRow(context),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _calendar(context),
                    _summary(context),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _presetDock(context),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SAKIYOMI',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: cs.primary)),
              const Text('アラーム',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nextAlarmBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final next = appStore.nextAlarm();
    String big;
    String sub;
    if (next == null) {
      big = '設定なし';
      sub = '';
    } else {
      big = next.alarm.timeLabel;
      final diff = appStore.daysFromToday(next.alarm.dateKey);
      final when = diff == 0
          ? '今日'
          : diff == 1
              ? '明日'
              : diff == 2
                  ? '明後日'
                  : '${next.when.month}/${next.when.day}';
      sub = '$when ・ ${next.alarm.label}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Material(
        color: cs.primary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: next == null ? null : () => showDaySheet(context, next.alarm.dateKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.notifications_active_outlined,
                      color: cs.onPrimary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('次のアラーム',
                          style: TextStyle(
                              color: cs.onPrimary.withValues(alpha: 0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(big,
                              style: TextStyle(
                                  color: cs.onPrimary,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          Text(sub,
                              style: TextStyle(
                                  color: cs.onPrimary.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (next != null)
                  Icon(Icons.edit_outlined,
                      color: cs.onPrimary.withValues(alpha: 0.9), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 14, 6),
      child: Row(
        children: [
          Text('$_year年 $_month月',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(
            onPressed: _goToday,
            style: TextButton.styleFrom(
                foregroundColor: cs.primary,
                backgroundColor: cs.primary.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('今日', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _prevMonth,
              icon: const Icon(Icons.chevron_left)),
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _nextMonth,
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }

  Widget _weekdayRow(BuildContext context) {
    const labels = ['日', '月', '火', '水', '木', '金', '土'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: List.generate(7, (i) {
          Color? c;
          if (i == 0) c = const Color(0xFFC9566A);
          if (i == 6) c = const Color(0xFF5A86C9);
          return Expanded(
            child: Center(
              child: Text(labels[i],
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: c)),
            ),
          );
        }),
      ),
    );
  }

  Widget _calendar(BuildContext context) {
    final first = DateTime(_year, _month, 1);
    final startCol = first.weekday % 7; // 日=0
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final totalCells = (((startCol + daysInMonth) + 6) ~/ 7) * 7;
    final weeks = totalCells ~/ 7;

    int? firstLockedWeek;
    for (var i = 0; i < totalCells; i++) {
      final dayNum = i - startCol + 1;
      if (dayNum < 1 || dayNum > daysInMonth) continue;
      final key = dateKeyOf(DateTime(_year, _month, dayNum));
      if (appStore.isLocked(key) && appStore.resolve(key) == null) {
        firstLockedWeek = i ~/ 7;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - 24) / 7;
        final cellH = cellW * 1.12;

        final weekRows = List.generate(weeks, (w) {
          return SizedBox(
            height: cellH,
            child: Row(
              children: List.generate(7, (col) {
                final i = w * 7 + col;
                return Expanded(child: _cell(context, i, startCol, daysInMonth));
              }),
            ),
          );
        });

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Stack(
            children: [
              Column(children: weekRows),
              if (firstLockedWeek != null)
                Positioned.fill(
                  child: Column(
                    children: [
                      Expanded(flex: firstLockedWeek, child: const SizedBox()),
                      Expanded(
                        flex: weeks - firstLockedWeek,
                        child: _unlockBand(context),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(BuildContext context, int i, int startCol, int daysInMonth) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final dayNum = i - startCol + 1;
    final inMonth = dayNum >= 1 && dayNum <= daysInMonth;

    if (!inMonth) {
      return const SizedBox();
    }

    final date = DateTime(_year, _month, dayNum);
    final key = dateKeyOf(date);
    final diff = appStore.daysFromToday(key);
    final isToday = diff == 0;
    final isPast = diff < 0;
    final locked = appStore.isLocked(key);
    final resolved = appStore.resolve(key);
    final off = appStore.dayIsOff(key);
    final dow = i % 7;

    Color dayNumColor = cs.onSurface.withValues(alpha: 0.7);
    if (dow == 0) dayNumColor = const Color(0xFFC9566A);
    if (dow == 6) dayNumColor = const Color(0xFF5A86C9);

    Widget content;
    Color? bg;
    Color borderColor = cs.outlineVariant;

    if (locked && resolved == null) {
      // 8日目以降＝ぼかし（フロスト）。ダミーの時刻を薄く表示。
      const ghosts = ['6:40', '7:00', '5:30', '休', '8:00', '7:30', '6:00'];
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Center(
          child: Text(ghosts[dayNum % 7],
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.35))),
        ),
      );
    } else if (resolved != null) {
      final color = PresetPalette.of(resolved.colorIndex, brightness);
      bg = Color.alphaBlend(color.withValues(alpha: 0.16), cs.surfaceContainerHighest);
      borderColor = color.withValues(alpha: 0.45);
      content = Center(
        child: Text(resolved.timeLabel,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      );
    } else if (off) {
      final color = PresetPalette.of(4, brightness);
      bg = Color.alphaBlend(color.withValues(alpha: 0.14), cs.surfaceContainerHighest);
      borderColor = color.withValues(alpha: 0.4);
      content = Center(
        child: Text('休',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      );
    } else {
      content = const SizedBox();
    }

    final cell = Opacity(
      opacity: isPast ? 0.45 : (locked && resolved == null ? 0.55 : 1.0),
      child: Container(
        margin: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: bg ?? cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isToday ? cs.primary : borderColor,
            width: isToday ? 1.6 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 5,
              left: 0,
              right: 0,
              child: Center(
                child: Text('$dayNum',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: dayNumColor)),
              ),
            ),
            Positioned.fill(child: content),
            if (appStore.dayPlans[key]?.hasOverride ?? false)
              Positioned(
                top: 5,
                right: 6,
                child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: cs.primary, shape: BoxShape.circle)),
              ),
          ],
        ),
      ),
    );

    if (isPast) return cell;

    return GestureDetector(
      onTap: () => _onTapDay(key, locked),
      child: cell,
    );
  }

  Widget _unlockBand(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showPaywall(context, reason: PaywallReason.locked),
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, Color.alphaBlend(const Color(0x887D54C8), cs.primary)],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: cs.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10)),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 18),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('8日目から先もまとめて設定',
                          style: TextStyle(
                              color: cs.onPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      Text('Proにアップグレードして解放',
                          style: TextStyle(
                              color: cs.onPrimary.withValues(alpha: 0.9),
                              fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(11)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('解放',
                          style: TextStyle(
                              color: cs.onPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      Icon(Icons.chevron_right, color: cs.onPrimary, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final s = appStore.monthSummary(_year, _month);
    Widget legend(Color c, String label, int n) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('$label ',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.7))),
            Text('$n日',
                style:
                    const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ],
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              legend(PresetPalette.of(1, brightness), 'アラーム', s.set),
              legend(PresetPalette.of(4, brightness), '休み', s.off),
              legend(cs.outlineVariant, '設定できる空き', s.empty),
            ],
          ),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                if (appStore.isPro) {
                  showRotationSheet(context, _year, _month);
                } else {
                  showPaywall(context, reason: PaywallReason.rotation);
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: cs.primary,
                backgroundColor: cs.primary.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              icon: const Icon(Icons.repeat, size: 18),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('くり返しでまとめて埋める',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('Pro',
                        style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetDock(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final hint = _brush == null
        ? 'プリセットを選んで塗る ・ 日付をタップで個別編集'
        : '「${appStore.presetById(_brush)?.name ?? ''}」を塗る ・ 日付をタップ（同じ日で解除）';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(hint,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: _brush == null ? FontWeight.w400 : FontWeight.w600,
                  color: _brush == null
                      ? cs.onSurface.withValues(alpha: 0.5)
                      : cs.primary)),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...appStore.presets.map((p) {
                  final color = PresetPalette.of(p.colorIndex, brightness);
                  final selected = _brush == p.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(
                          () => _brush = selected ? null : p.id),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? Color.alphaBlend(
                                  color.withValues(alpha: 0.14), cs.surface)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: selected ? color : cs.outlineVariant,
                              width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                    color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 7),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                Text(p.isDayOff ? '休み' : p.timeLabel,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.5))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => DefaultTabController.maybeOf(context) == null
                        ? _openPresets(context)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add,
                              size: 18,
                              color: cs.onSurface.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Text('追加',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withValues(alpha: 0.7))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openPresets(BuildContext context) {
    // プリセット追加はプリセットタブへ誘導（簡易）。
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('下の「プリセット」タブから追加・編集できます'),
      duration: Duration(seconds: 2),
    ));
  }
}
