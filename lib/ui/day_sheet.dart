import 'package:flutter/material.dart';

import '../constants.dart';
import '../data/app_store.dart';
import '../services/services.dart';

void showDaySheet(BuildContext context, String dateKey) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _DaySheet(dateKey: dateKey),
  );
}

class _DaySheet extends StatefulWidget {
  final String dateKey;
  const _DaySheet({required this.dateKey});

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  int _h = 7;
  int _m = 0;

  @override
  void initState() {
    super.initState();
    final r = appStore.resolve(widget.dateKey);
    if (r != null) {
      _h = r.hour;
      _m = r.minute;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final date = parseDateKey(widget.dateKey);
    const wd = ['日', '月', '火', '水', '木', '金', '土'];
    final title = '${date.month}月${date.day}日(${wd[date.weekday % 7]})';
    final r = appStore.resolve(widget.dateKey);
    final off = appStore.dayIsOff(widget.dateKey);

    String status;
    if (r != null) {
      status = '${r.timeLabel} ・ ${r.label}${r.isOverride ? '（この日だけ）' : ''}';
    } else if (off) {
      status = '休み ・ アラームなし';
    } else {
      status = 'まだ設定なし';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grab(cs),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(status,
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: 16),
          _label('プリセットを選ぶ', cs),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: appStore.presets.map((p) {
              final color = PresetPalette.of(p.colorIndex, brightness);
              final plan = appStore.dayPlans[widget.dateKey];
              final selected =
                  plan?.presetId == p.id && !(plan?.hasOverride ?? false);
              return GestureDetector(
                onTap: () async {
                  await appStore.assignPreset(widget.dateKey, p.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? Color.alphaBlend(color.withValues(alpha: 0.14), cs.surface)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: selected ? color : cs.outlineVariant, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 7),
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Text(p.isDayOff ? '休み' : p.timeLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _label('またはこの日だけの時刻にする', cs),
          const SizedBox(height: 8),
          _timePicker(cs),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await appStore.setOverride(widget.dateKey, _h, _m);
                if (context.mounted) Navigator.pop(context);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('この時刻でこの日だけ設定'),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                await appStore.clearDay(widget.dateKey);
                if (context.mounted) Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC9566A)),
              child: const Text('この日のアラームを消す'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timePicker(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepper(
              onUp: () => setState(() => _h = (_h + 1) % 24),
              onDown: () => setState(() => _h = (_h + 23) % 24),
              cs: cs),
          const SizedBox(width: 6),
          Text(_h.toString().padLeft(2, '0'),
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          Text(' : ',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withValues(alpha: 0.4))),
          Text(_m.toString().padLeft(2, '0'),
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          _stepper(
              onUp: () => setState(() => _m = (_m + 5) % 60),
              onDown: () => setState(() => _m = (_m + 55) % 60),
              cs: cs),
        ],
      ),
    );
  }

  Widget _stepper(
      {required VoidCallback onUp,
      required VoidCallback onDown,
      required ColorScheme cs}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(Icons.keyboard_arrow_up, onUp, cs),
        const SizedBox(height: 5),
        _stepBtn(Icons.keyboard_arrow_down, onDown, cs),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap, ColorScheme cs) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 28,
        decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant)),
        child: Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _grab(ColorScheme cs) => Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14, top: 6),
        decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2)),
      );

  Widget _label(String s, ColorScheme cs) => Align(
        alignment: Alignment.centerLeft,
        child: Text(s,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: cs.onSurface.withValues(alpha: 0.5))),
      );
}
