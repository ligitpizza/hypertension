import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / dark / follow-system theme choice, saved on the device.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = ThemeMode.values.where((m) => m.name == prefs.getString(_key)).firstOrNull;
      if (saved != null) state = saved;
    } catch (_) {
      // No storage available (e.g. tests): keep the default.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Choice still applies for this session.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

String themeModeLabel(ThemeMode m) => switch (m) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

IconData themeModeIcon(ThemeMode m) => switch (m) {
  ThemeMode.system => Icons.brightness_auto,
  ThemeMode.light => Icons.light_mode,
  ThemeMode.dark => Icons.dark_mode,
};

/// System / Light / Dark segmented selector (patient More tab).
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      key: const Key('theme-selector'),
      showSelectedIcon: false,
      segments: [
        for (final m in ThemeMode.values)
          ButtonSegment(value: m, icon: Icon(themeModeIcon(m)), label: Text(themeModeLabel(m))),
      ],
      selected: {mode},
      onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
    );
  }
}

/// Compact app-bar button with a menu (family app, staff portal).
class ThemeModeMenuButton extends ConsumerWidget {
  const ThemeModeMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return PopupMenuButton<ThemeMode>(
      key: const Key('theme-menu'),
      tooltip: 'Theme',
      icon: Icon(themeModeIcon(mode)),
      initialValue: mode,
      onSelected: (m) => ref.read(themeModeProvider.notifier).set(m),
      itemBuilder: (_) => [
        for (final m in ThemeMode.values)
          PopupMenuItem(
            value: m,
            child: ListTile(leading: Icon(themeModeIcon(m)), title: Text(themeModeLabel(m))),
          ),
      ],
    );
  }
}
