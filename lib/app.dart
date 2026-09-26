import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'pages/home_page.dart';
import 'ui_settings.dart';

class FilterlosApp extends StatelessWidget {
  const FilterlosApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.settings;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'filterlos.ich',
          theme: buildFilterlosTheme(settings, stealth: false),
          darkTheme: buildFilterlosTheme(
            settings,
            stealth: settings.stealthMode,
          ),
          themeMode: settings.useLightTheme && !settings.stealthMode
              ? ThemeMode.light
              : ThemeMode.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(settings.textScaleFactor)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: FilterlosHomePage(controller: controller),
        );
      },
    );
  }
}
