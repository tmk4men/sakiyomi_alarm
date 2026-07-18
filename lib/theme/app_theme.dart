import 'package:flutter/material.dart';

/// さきよみアラームの配色。やわらかい朝の空気感（オフホワイト地＋トワイライト・インディゴ）。
class AppTheme {
  static const Color _primaryLight = Color(0xFF4E5BD6);
  static const Color _primaryDark = Color(0xFF828CF2);

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: _primaryLight,
      onPrimary: Colors.white,
      surface: Color(0xFFFEFCFA),
      onSurface: Color(0xFF211F27),
      surfaceContainerHighest: Color(0xFFF6F1EF),
      outlineVariant: Color(0xFFE3DFD6),
      secondary: Color(0xFFD98A24),
    );
    return _base(scheme, const Color(0xFFF3ECEA));
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: _primaryDark,
      onPrimary: Color(0xFF0B0B0F),
      surface: Color(0xFF1C1B24),
      onSurface: Color(0xFFECEBF0),
      surfaceContainerHighest: Color(0xFF24222D),
      outlineVariant: Color(0xFF2A2A33),
      secondary: Color(0xFFE1A24B),
    );
    return _base(scheme, const Color(0xFF14131A));
  }

  static ThemeData _base(ColorScheme scheme, Color scaffold) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: null, // 端末のシステム日本語フォント（Hiragino/Noto）を使用
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: Typography.material2021().black.apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          ),
    );
  }

  /// ホーム背景のやわらかいグラデーション。
  static BoxDecoration screenGradient(Brightness b) {
    if (b == Brightness.dark) {
      return const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1722), Color(0xFF151420), Color(0xFF12121C)],
        ),
      );
    }
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFFAEDE6), Color(0xFFF2ECEE), Color(0xFFECEAF2)],
      ),
    );
  }
}
