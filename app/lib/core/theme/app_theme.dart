import 'package:flutter/material.dart';

/// Single Material 3 theme shared by all three entrypoints (docs/07 "Visual system").
abstract final class AppTheme {
  static const _seed = Color(0xFF1D6FA3); // clinical blue

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // NFR-3.1: minimum 48 dp touch targets.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
    );
  }
}

/// BP category colours (docs/06 §E). Used for all BP/risk badges.
abstract final class BpColors {
  static const normal = Color(0xFF1D9E75);
  static const elevated = Color(0xFFEF9F27);
  static const stage1 = Color(0xFFD85A30);
  static const stage2 = Color(0xFFE24B4A);
  static const crisis = Color(0xFFA32D2D);
}
