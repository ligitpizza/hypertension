import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/theme/app_theme.dart';
import 'package:hypertension/core/theme/theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

/// Minimal app that applies the chosen theme mode like CareFlowApp does.
class _App extends ConsumerWidget {
  const _App(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ref.watch(themeModeProvider),
    home: Scaffold(body: Center(child: child)),
  );
}

ThemeMode appliedMode(WidgetTester t) => t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tallTest('defaults to System and switches to Light and Dark', (t) async {
    await t.pumpWidget(const ProviderScope(child: _App(ThemeModeSelector())));
    await t.pumpAndSettle();
    expect(appliedMode(t), ThemeMode.system);

    await t.tap(find.text('Light'));
    await t.pumpAndSettle();
    expect(appliedMode(t), ThemeMode.light);

    await t.tap(find.text('Dark'));
    await t.pumpAndSettle();
    expect(appliedMode(t), ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  tallTest('restores the saved choice on start', (t) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    await t.pumpWidget(const ProviderScope(child: _App(ThemeModeSelector())));
    await t.pumpAndSettle();
    expect(appliedMode(t), ThemeMode.light);
  });

  tallTest('app-bar menu changes the theme', (t) async {
    await t.pumpWidget(const ProviderScope(child: _App(ThemeModeMenuButton())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('theme-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Dark').last);
    await t.pumpAndSettle();
    expect(appliedMode(t), ThemeMode.dark);
  });
}
