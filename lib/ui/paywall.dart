import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../services/services.dart';

enum PaywallReason { locked, rotation, preset, menu }

void showPaywall(BuildContext context, {required PaywallReason reason}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _Paywall(reason: reason),
  );
}

class _Paywall extends StatefulWidget {
  final PaywallReason reason;
  const _Paywall({required this.reason});

  @override
  State<_Paywall> createState() => _PaywallState();
}

class _PaywallState extends State<_Paywall> {
  String _plan = Products.lifetime;

  String get _subText {
    switch (widget.reason) {
      case PaywallReason.locked:
        return '無料では今日から7日先まで。もっと先の予定も埋めるにはPro。';
      case PaywallReason.preset:
        return '無料はプリセット3個まで。仕事も旅行も自由に増やすにはPro。';
      case PaywallReason.rotation:
        return 'くり返し自動生成はPro機能。期間まとめて一気に埋められます。';
      case PaywallReason.menu:
        return '無料では7日先まで設定できます。もっと先まで、迷わず埋めるにはPro。';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: billingService,
      builder: (context, _) {
        final monthly = billingService.productById(Products.monthly);
        final lifetime = billingService.productById(Products.lifetime);
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14, top: 6),
                  decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const Text('1ヶ月分を、今夜まとめて',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(_subText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.7))),
                const SizedBox(height: 16),
                _feature(cs, '7日より先もまとめて設定', '来週・来月・帰省や旅行の予定も先に埋められる'),
                _feature(cs, 'プリセット無制限', '無料は3個まで。仕事も旅行も自由に登録'),
                _feature(cs, 'くり返し自動生成', '「早番3・休1」などを期間まとめて流し込み'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _planCard(
                        cs,
                        selected: _plan == Products.monthly,
                        title: '月額',
                        price: monthly?.price ?? '¥400',
                        sub: '/ 月',
                        onTap: () => setState(() => _plan = Products.monthly),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _planCard(
                        cs,
                        selected: _plan == Products.lifetime,
                        title: '買い切り',
                        price: lifetime?.price ?? '¥900',
                        sub: '一度だけ',
                        badge: 'ずっと使える',
                        onTap: () => setState(() => _plan = Products.lifetime),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: billingService.purchasePending ? null : _buy,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15)),
                    child: billingService.purchasePending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            _plan == Products.lifetime
                                ? '買い切りで購入 ・ ${lifetime?.price ?? '¥900'}'
                                : '月額 ${monthly?.price ?? '¥400'} で購読',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    TextButton(
                        onPressed: () => billingService.restore(),
                        child: const Text('購入を復元',
                            style: TextStyle(fontSize: 11.5))),
                    TextButton(
                        onPressed: () => _open(kTermsUrl),
                        child: const Text('利用規約',
                            style: TextStyle(fontSize: 11.5))),
                    TextButton(
                        onPressed: () => _open(kPrivacyUrl),
                        child: const Text('プライバシー',
                            style: TextStyle(fontSize: 11.5))),
                  ],
                ),
                Text(
                  _plan == Products.lifetime
                      ? '一度の購入で永続的に使えます（サブスクではありません）。'
                          '${lifetime?.price ?? '¥900'}（税込）の買い切りです。'
                      : '月額 ${monthly?.price ?? '¥400'}（税込）／月の自動更新サブスクです。'
                          '期間終了の24時間前までに解約しない限り自動更新されます。解約はApp Storeの購読管理から。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.5)),
                ),
                Text(
                  'サービス終了時は有料機能が使えなくなる場合があります（利用規約 第5条）。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.4)),
                ),
                if (billingService.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(billingService.lastError!,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFC9566A))),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _buy() async {
    final product = billingService.productById(_plan);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('商品情報を取得できませんでした（ストア接続を確認してください）'),
      ));
      return;
    }
    await billingService.buy(product);
  }

  Widget _feature(ColorScheme cs, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7)),
            child: Icon(Icons.check, size: 14, color: cs.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(desc,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(ColorScheme cs,
      {required bool selected,
      required String title,
      required String price,
      required String sub,
      String? badge,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(cs.primary.withValues(alpha: 0.1), cs.surface)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant, width: 1.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.7))),
                const SizedBox(height: 3),
                Text(price,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurface.withValues(alpha: 0.5))),
              ],
            ),
            if (badge != null)
              Positioned(
                top: -20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(badge,
                        style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
