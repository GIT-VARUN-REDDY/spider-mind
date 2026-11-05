import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/misc.dart';
import 'state/app_state.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class SpiderApp extends StatelessWidget {
  const SpiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeModeSetting>((s) => s.settings.theme);
    return MaterialApp(
      title: 'SpiderMind',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: buildTheme(Brightness.dark),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (mode) {
        ThemeModeSetting.light => ThemeMode.light,
        ThemeModeSetting.dark => ThemeMode.dark,
        ThemeModeSetting.system => ThemeMode.dark,
      },
      home: const RootGate(),
    );
  }
}
