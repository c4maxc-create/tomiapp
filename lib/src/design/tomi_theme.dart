import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'tomi_tokens.dart';

class TomiTheme {
  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: TomiColors.accent,
          brightness: Brightness.dark,
          surface: TomiColors.surface,
        ).copyWith(
          primary: TomiColors.accent,
          onPrimary: TomiColors.background,
          secondary: TomiColors.gold,
          onSurface: TomiColors.text,
          outline: TomiColors.border,
          error: TomiColors.pink,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TomiRadius.control),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: TomiColors.background,
      dividerColor: TomiColors.border,
      cardTheme: CardThemeData(
        color: TomiColors.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TomiRadius.card),
          side: const BorderSide(color: TomiColors.border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: TomiColors.accent,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        subtitleTextStyle: TextStyle(
          color: TomiColors.muted,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TomiColors.background,
        foregroundColor: TomiColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TomiColors.surface,
        indicatorColor: TomiColors.accent.withValues(alpha: .16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TomiColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TomiRadius.sheet),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: TomiColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TomiColors.raised,
        hintStyle: const TextStyle(color: TomiColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TomiRadius.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TomiRadius.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TomiRadius.control),
          borderSide: const BorderSide(color: TomiColors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          minimumSize: const Size(48, 46),
          side: const BorderSide(color: TomiColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TomiColors.raised,
        contentTextStyle: const TextStyle(color: TomiColors.text),
        shape: shape,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TomiColors.accent,
      ),
    );
  }
}
