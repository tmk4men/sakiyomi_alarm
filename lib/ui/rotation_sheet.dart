import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/services.dart';

void showRotationSheet(BuildContext context, int year, int month) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => const _RotationSheet(),
  );
}

class _RotationSheet extends StatefulWidget {
  const _RotationSheet();

  @override
  State<_RotationSheet> createState() => _RotationSheetState();
}

class _RotationSheetState extends State<_RotationSheet> {
  final List<String> _seq = [];
  int _days = 14;

  @override
  void initState() {
    super.initState();
    // 既定: 早番×3・休み（存在すれば）。
    for (final p in appStore.presets) {
      if (p.name.contains('早')) {
        _seq.addAll([p.id, p.id, p.id]);
        break;
      }
    }
    for (final p in appStore.presets) {
      if (p.isDayOff) {
        _seq.add(p.id);
        break;
      }
    }
    if (_seq.isEmpty && appStore.presets.isNotEmpty) {
      _seq.add(appStore.presets.first.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    String seqNames() => _seq
        .map((id) {
          final p = appStore.presetById(id);
          return p == null ? '' : (p.isDayOff ? '休' : p.name);
        })
        .join(' → ');

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14, top: 6),
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Center(
                child: Text('くり返しで埋める',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            const SizedBox(height: 4),
            Center(
              child: Text('パターンを組んで、期間にまとめて流し込み。',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.7))),
            ),
            const SizedBox(height: 16),
            _label('くり返す並び', cs),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (_seq.isEmpty)
                  Text('下からパターンを足してください',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5))),
                ..._seq.asMap().entries.map((e) {
                  final p = appStore.presetById(e.value);
                  final color = p == null
                      ? cs.primary
                      : PresetPalette.of(p.colorIndex, brightness);
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p == null ? '' : (p.isDayOff ? '休み' : p.name),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _seq.removeAt(e.key)),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: appStore.presets.map((p) {
                final color = PresetPalette.of(p.colorIndex, brightness);
                return OutlinedButton(
                  onPressed: () => setState(() => _seq.add(p.id)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface.withValues(alpha: 0.8),
                    side: BorderSide(color: cs.outlineVariant),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            _label('期間', cs),
            const SizedBox(height: 8),
            Row(
              children: [
                _range(cs, 14, '2週間'),
                const SizedBox(width: 8),
                _range(cs, 30, '1ヶ月'),
                const SizedBox(width: 8),
                _range(cs, 60, '2ヶ月'),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(
                _seq.isEmpty
                    ? 'パターンが空です'
                    : '今日から$_days日間、${seqNames()} をくり返します',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _seq.isEmpty
                    ? null
                    : () async {
                        await appStore.applyRotation(_seq, _days);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('$_days日分をまとめて設定しました')));
                        }
                      },
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                child: const Text('この内容で埋める',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _range(ColorScheme cs, int days, String label) {
    final selected = _days == days;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _days = days),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(cs.primary.withValues(alpha: 0.1), cs.surface)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant, width: 1.5),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              Text('今日から',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: cs.onSurface.withValues(alpha: 0.5))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String s, ColorScheme cs) => Text(s,
      style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.onSurface.withValues(alpha: 0.5)));
}
