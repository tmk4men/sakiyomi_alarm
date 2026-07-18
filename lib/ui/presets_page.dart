import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/preset.dart';
import '../services/services.dart';
import 'paywall.dart';

class PresetsPage extends StatelessWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return ListenableBuilder(
      listenable: appStore,
      builder: (context, _) {
        final presets = appStore.presets;
        final atLimit = !appStore.isPro && presets.length >= kMaxPresetsFree;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('プリセット',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text('よく使う起床パターンを登録。カレンダーで選んで塗るだけ。',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.6))),
            ),
            ...presets.map((p) {
              final color = PresetPalette.of(p.colorIndex, brightness);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openEditor(context, p),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(5))),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    p.isDayOff
                                        ? 'アラームなし（休み）'
                                        : '毎回この時刻で起こす',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.5))),
                              ],
                            ),
                          ),
                          Text(p.isDayOff ? '休み' : p.timeLabel,
                              style: TextStyle(
                                  fontSize: p.isDayOff ? 14 : 19,
                                  fontWeight: FontWeight.w800,
                                  color: p.isDayOff
                                      ? PresetPalette.of(4, brightness)
                                      : cs.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () {
                if (atLimit) {
                  showPaywall(context, reason: PaywallReason.preset);
                } else {
                  _openEditor(context, null);
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface.withValues(alpha: 0.7),
                side: BorderSide(color: cs.outlineVariant, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.add),
              label: Text(atLimit ? 'プリセットを追加（Pro）' : 'プリセットを追加'),
            ),
            const SizedBox(height: 8),
            Text(
              atLimit
                  ? '無料プランはプリセット3個まで。Proで無制限に。'
                  : '無料プランはあと${kMaxPresetsFree - presets.length}個まで登録できます。',
              style: TextStyle(
                  fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        );
      },
    );
  }

  void _openEditor(BuildContext context, Preset? preset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _PresetEditor(preset: preset),
    );
  }
}

class _PresetEditor extends StatefulWidget {
  final Preset? preset;
  const _PresetEditor({this.preset});

  @override
  State<_PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends State<_PresetEditor> {
  late TextEditingController _name;
  late bool _off;
  late int _h;
  late int _m;
  late int _color;
  late String _soundId;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _name = TextEditingController(text: p?.name ?? '');
    _off = p?.isDayOff ?? false;
    _h = p?.hour ?? 6;
    _m = p?.minute ?? 30;
    _color = p?.colorIndex ?? 3;
    _soundId = p?.soundId ?? BuiltinSounds.defaultId;
  }

  @override
  void dispose() {
    _name.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _preview(String id) async {
    final asset = BuiltinSounds.assetFor(id);
    if (asset == null) return; // 「標準」は試聴なし
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isNew = widget.preset == null;

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
            Center(
              child: Text(isNew ? '新しいプリセット' : 'プリセットを編集',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 16),
            _label('名前', cs),
            const SizedBox(height: 7),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: '例：早番 / 旅行 / 通院',
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _off = !_off),
              borderRadius: BorderRadius.circular(13),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13)),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('休みの日（アラームなし）',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                          Text('この色を塗った日は鳴りません',
                              style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                        value: _off,
                        onChanged: (v) => setState(() => _off = v)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (!_off) ...[
              _label('起こす時刻', cs),
              const SizedBox(height: 7),
              _timePicker(cs),
              const SizedBox(height: 14),
            ],
            _label('色', cs),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(PresetPalette.count, (i) {
                final color = PresetPalette.of(i, brightness);
                final sel = _color == i;
                return GestureDetector(
                  onTap: () => setState(() => _color = i),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: sel ? cs.onSurface : Colors.transparent,
                          width: 2.5),
                    ),
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }),
            ),
            if (!_off) ...[
              const SizedBox(height: 14),
              _label('アラーム音', cs),
              const SizedBox(height: 8),
              Column(
                children: BuiltinSounds.all.map((s) {
                  final sel = _soundId == s.id;
                  final canPreview = BuiltinSounds.assetFor(s.id) != null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _soundId = s.id);
                        _preview(s.id);
                      },
                      borderRadius: BorderRadius.circular(13),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: sel
                              ? Color.alphaBlend(
                                  cs.primary.withValues(alpha: 0.1), cs.surface)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                              color: sel ? cs.primary : cs.outlineVariant,
                              width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              sel
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: sel ? cs.primary : cs.onSurface.withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(s.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (canPreview)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _preview(s.id),
                                icon: Icon(Icons.play_circle_outline,
                                    color: cs.primary),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                child: const Text('保存',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
            if (!isNew)
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await appStore.deletePreset(widget.preset!.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC9566A)),
                  child: const Text('このプリセットを削除'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? '新規' : _name.text.trim();
    final existing = widget.preset;
    final preset = Preset(
      id: existing?.id ?? 'p_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      hour: _off ? null : _h,
      minute: _off ? null : _m,
      colorIndex: _color,
      soundId: _soundId,
      snoozeMinutes: existing?.snoozeMinutes ?? appStore.defaultSnooze,
      vibrate: existing?.vibrate ?? true,
    );
    await appStore.upsertPreset(preset);
    if (mounted) Navigator.pop(context);
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
          _stepper(() => setState(() => _h = (_h + 1) % 24),
              () => setState(() => _h = (_h + 23) % 24), cs),
          const SizedBox(width: 6),
          Text(_h.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          Text(' : ',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withValues(alpha: 0.4))),
          Text(_m.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          _stepper(() => setState(() => _m = (_m + 5) % 60),
              () => setState(() => _m = (_m + 55) % 60), cs),
        ],
      ),
    );
  }

  Widget _stepper(VoidCallback up, VoidCallback down, ColorScheme cs) {
    Widget btn(IconData i, VoidCallback t) => InkWell(
          onTap: t,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 28,
            decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant)),
            child:
                Icon(i, size: 18, color: cs.onSurface.withValues(alpha: 0.7)),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.keyboard_arrow_up, up),
        const SizedBox(height: 5),
        btn(Icons.keyboard_arrow_down, down),
      ],
    );
  }

  Widget _label(String s, ColorScheme cs) => Text(s,
      style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.onSurface.withValues(alpha: 0.5)));
}
