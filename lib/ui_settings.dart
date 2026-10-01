import 'package:flutter/material.dart';

class FilterlosSettings {
  const FilterlosSettings({
    required this.fontFamily,
    required this.textScaleFactor,
    required this.useLightTheme,
    required this.accentColorValue,
    required this.highlightColorValue,
    required this.stealthMode,
    required this.emojiButtons,
    required this.biometricTimeline,
    required this.localModelPath,
    required this.embeddingModelPath,
    required this.userMemorySummary,
  });

  static const availableFonts = <String>[
    'OpenDyslexic',
    'NotoSans',
    'CourierPrime',
    'Ubuntu',
    'Ubuntu Mono',
  ];

  static const colors = <int, String>{
    0xFFE57373: 'Rot',
    0xFFFFB74D: 'Orange',
    0xFFAED581: 'Grün',
    0xFFFFF176: 'Gelb',
    0xFF64B5F6: 'Blau',
    0xFF8FDCBE: 'Mint',
    0xFF9575CD: 'Lila',
  };

  static const defaults = FilterlosSettings(
    fontFamily: 'Ubuntu',
    textScaleFactor: 1,
    useLightTheme: false,
    accentColorValue: 0xFFE57373,
    highlightColorValue: 0xFFFFB74D,
    stealthMode: false,
    emojiButtons: true,
    biometricTimeline: false,
    localModelPath: '',
    embeddingModelPath: '',
    userMemorySummary: '',
  );

  final String fontFamily;
  final double textScaleFactor;
  final bool useLightTheme;
  final int accentColorValue;
  final int highlightColorValue;
  final bool stealthMode;
  final bool emojiButtons;
  final bool biometricTimeline;
  final String localModelPath;
  final String embeddingModelPath;
  final String userMemorySummary;

  FilterlosSettings copyWith({
    String? fontFamily,
    double? textScaleFactor,
    bool? useLightTheme,
    int? accentColorValue,
    int? highlightColorValue,
    bool? stealthMode,
    bool? emojiButtons,
    bool? biometricTimeline,
    String? localModelPath,
    String? embeddingModelPath,
    String? userMemorySummary,
  }) {
    return FilterlosSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      useLightTheme: useLightTheme ?? this.useLightTheme,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      highlightColorValue: highlightColorValue ?? this.highlightColorValue,
      stealthMode: stealthMode ?? this.stealthMode,
      emojiButtons: emojiButtons ?? this.emojiButtons,
      biometricTimeline: biometricTimeline ?? this.biometricTimeline,
      localModelPath: localModelPath ?? this.localModelPath,
      embeddingModelPath: embeddingModelPath ?? this.embeddingModelPath,
      userMemorySummary: userMemorySummary ?? this.userMemorySummary,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontFamily': fontFamily,
    'textScaleFactor': textScaleFactor,
    'useLightTheme': useLightTheme,
    'accentColorValue': accentColorValue,
    'highlightColorValue': highlightColorValue,
    'stealthMode': stealthMode,
    'emojiButtons': emojiButtons,
    'biometricTimeline': biometricTimeline,
    'localModelPath': localModelPath,
    'embeddingModelPath': embeddingModelPath,
    'userMemorySummary': userMemorySummary,
  };

  factory FilterlosSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final font = json['fontFamily'] as String?;
    final scale = (json['textScaleFactor'] as num?)?.toDouble() ?? 1;
    final accent = (json['accentColorValue'] as num?)?.toInt();
    final highlight = (json['highlightColorValue'] as num?)?.toInt();
    return FilterlosSettings(
      fontFamily: availableFonts.contains(font) ? font! : defaults.fontFamily,
      textScaleFactor: scale.clamp(0.5, 1.6),
      useLightTheme: json['useLightTheme'] as bool? ?? defaults.useLightTheme,
      accentColorValue: colors.containsKey(accent)
          ? accent!
          : defaults.accentColorValue,
      highlightColorValue: colors.containsKey(highlight)
          ? highlight!
          : defaults.highlightColorValue,
      stealthMode: json['stealthMode'] as bool? ?? false,
      emojiButtons: json['emojiButtons'] as bool? ?? true,
      biometricTimeline: json['biometricTimeline'] as bool? ?? false,
      localModelPath: json['localModelPath'] as String? ?? '',
      embeddingModelPath: json['embeddingModelPath'] as String? ?? '',
      userMemorySummary: json['userMemorySummary'] as String? ?? '',
    );
  }
}

ThemeData buildFilterlosTheme(
  FilterlosSettings settings, {
  required bool stealth,
}) {
  final brightness = settings.useLightTheme && !stealth
      ? Brightness.light
      : Brightness.dark;
  final accent = stealth
      ? const Color(0xFF8A8A8A)
      : Color(settings.accentColorValue);
  final highlight = stealth
      ? const Color(0xFFBDBDBD)
      : Color(settings.highlightColorValue);
  final base = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  final scheme = base.copyWith(
    primary: accent,
    onPrimary: stealth ? Colors.black : base.onPrimary,
    primaryContainer: stealth ? const Color(0xFF303030) : base.primaryContainer,
    onPrimaryContainer: stealth
        ? const Color(0xFFE0E0E0)
        : base.onPrimaryContainer,
    secondary: highlight,
    onSecondary: stealth ? Colors.black : base.onSecondary,
    secondaryContainer: stealth
        ? const Color(0xFF303030)
        : base.secondaryContainer,
    onSecondaryContainer: stealth
        ? const Color(0xFFE0E0E0)
        : base.onSecondaryContainer,
    tertiary: highlight,
    onTertiary: stealth ? Colors.black : base.onTertiary,
    error: stealth ? const Color(0xFFBDBDBD) : base.error,
    onError: stealth ? Colors.black : base.onError,
    outline: stealth ? const Color(0xFF777777) : base.outline,
    surface: stealth ? Colors.black : base.surface,
    onSurface: stealth ? const Color(0xFF777777) : base.onSurface,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: settings.fontFamily,
    scaffoldBackgroundColor: stealth ? Colors.black : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: stealth ? Colors.black : null,
      iconTheme: IconThemeData(color: highlight),
      actionsIconTheme: IconThemeData(color: highlight),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: highlight),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: highlight,
        foregroundColor: Colors.black,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: highlight, width: 2),
      ),
      floatingLabelStyle: TextStyle(color: highlight),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: stealth
          ? const Color(0xFF101010)
          : const Color(0xFF242424),
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: highlight,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: highlight,
      selectionColor: highlight.withAlpha(80),
      selectionHandleColor: highlight,
    ),
  );
}
