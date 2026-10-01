import 'package:flutter/material.dart';

/// 应用主题 —— 支持 Material You 动态取色（原项目用 `dynamic_color`）。
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF4AAD4E);

  static ThemeData light({ColorScheme? dynamicScheme}) {
    final ColorScheme scheme = dynamicScheme ??
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return _base(scheme);
  }

  static ThemeData dark({ColorScheme? dynamicScheme}) {
    final ColorScheme scheme = dynamicScheme ??
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}
