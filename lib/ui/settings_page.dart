import 'package:flutter/material.dart';

import '../services/services.dart';
import 'paywall.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: appStore,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('設定',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            if (appStore.isPro)
              _proActiveCard(cs)
            else
              _proCard(context, cs),
            const SizedBox(height: 18),
            _sectionLabel('表示', cs),
            _group(cs, [
              _themeRow(context, cs),
            ]),
            const SizedBox(height: 18),
            _sectionLabel('アラーム', cs),
            _group(cs, [
              _snoozeRow(context, cs),
              _tile(cs, '通知を許可', trailing: TextButton(
                onPressed: () => notificationService.requestPermissions(),
                child: const Text('リクエスト'),
              )),
            ]),
            const SizedBox(height: 20),
            Center(
              child: Text('さきよみアラーム v1.0.0',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurface.withValues(alpha: 0.5))),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'iOSではローカル通知でお知らせします。\n確実に起きるため通知の許可と、集中モードでの許可設定を推奨します。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.45)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _proCard(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(cs.primary.withValues(alpha: 0.22), cs.surface),
            cs.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Color.alphaBlend(
                cs.primary.withValues(alpha: 0.3), cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: cs.primary),
              const SizedBox(width: 7),
              const Text('Proにアップグレード',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text('7日より先までまとめて設定・プリセット無制限・くり返し自動生成。',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: cs.onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => showPaywall(context, reason: PaywallReason.menu),
            child: const Text('詳しく見る'),
          ),
        ],
      ),
    );
  }

  Widget _proActiveCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: cs.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Pro 有効 — すべての機能が使えます',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _themeRow(BuildContext context, ColorScheme cs) {
    String label(ThemeMode m) => switch (m) {
          ThemeMode.system => '端末に合わせる',
          ThemeMode.light => 'ライト',
          ThemeMode.dark => 'ダーク',
        };
    return _tile(
      cs,
      'テーマ',
      trailing: DropdownButton<ThemeMode>(
        value: appStore.themeMode,
        underline: const SizedBox(),
        items: ThemeMode.values
            .map((m) => DropdownMenuItem(value: m, child: Text(label(m))))
            .toList(),
        onChanged: (m) {
          if (m != null) appStore.setThemeMode(m);
        },
      ),
    );
  }

  Widget _snoozeRow(BuildContext context, ColorScheme cs) {
    return _tile(
      cs,
      '既定のスヌーズ',
      trailing: DropdownButton<int>(
        value: appStore.defaultSnooze,
        underline: const SizedBox(),
        items: const [3, 5, 10, 15]
            .map((m) => DropdownMenuItem(value: m, child: Text('$m分')))
            .toList(),
        onChanged: (m) {
          if (m != null) appStore.setDefaultSnooze(m);
        },
      ),
    );
  }

  Widget _group(ColorScheme cs, List<Widget> children) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(Divider(height: 1, color: cs.outlineVariant));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(children: items),
    );
  }

  Widget _tile(ColorScheme cs, String label, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _sectionLabel(String s, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(s,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.onSurface.withValues(alpha: 0.5))),
      );
}
