import 'package:flutter/material.dart';

/// 無料プランで今日から設定できる日数（これより先はProで解放）。
const int kFreeDaysAhead = 7;

/// 無料プランで登録できるプリセット数。
const int kMaxPresetsFree = 3;

/// iOS の保留中ローカル通知の上限(64)に対する安全なスケジュール上限。
/// スヌーズ用の枠を残すため 55 に抑える。
const int kMaxScheduledAlarms = 55;

/// 法的文書のURL（GitHub Pages）。
const String kTermsUrl = 'https://tmk4men.github.io/sakiyomi_alarm/terms.html';
const String kPrivacyUrl = 'https://tmk4men.github.io/sakiyomi_alarm/privacy.html';

/// アプリ内課金のプロダクトID。
/// - monthly: 自動更新サブスク（月額¥400）
/// - lifetime: 買い切り（非消費型・¥900）
class Products {
  static const String monthly = 'sakiyomi_pro_monthly';
  static const String lifetime = 'sakiyomi_pro_lifetime';
  static const List<String> subs = [monthly];
  static const List<String> inApp = [lifetime];
  static const List<String> all = [monthly, lifetime];
}

/// プリセットの色パレット（インデックスで参照）。
class PresetPalette {
  static const List<Color> light = [
    Color(0xFF5866C7), // indigo
    Color(0xFFD98A24), // amber
    Color(0xFF2C9E92), // teal
    Color(0xFFCE5B7B), // rose
    Color(0xFF93909A), // grey (休み向け)
  ];
  static const List<Color> dark = [
    Color(0xFF8189E8),
    Color(0xFFE1A24B),
    Color(0xFF3FBAAC),
    Color(0xFFE1789A),
    Color(0xFF7C7A85),
  ];

  static Color of(int index, Brightness b) {
    final list = b == Brightness.dark ? dark : light;
    return list[index % list.length];
  }

  static int get count => light.length;
}
