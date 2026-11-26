import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;

import 'app_state.dart';
import 'ui/splash.dart';

// The page's own --paper, so the app's screens match the plate.
const paper = Color(0xFFEEE5CE);
const ink = Color(0xFF2A241C);
// The rest of the page's palette (its :root), so the app's own controls
// wear the plate's colours rather than Material's pinks.
const madder = Color(0xFF8C3B2A);
const paperDeep = Color(0xFFE3D7B8);
const sepia = Color(0xFF6B5338);
const rule = Color(0xFFBCAB86);

// The plate's typefaces: IM Fell English for text, its small caps for
// headings, as the page uses them.
const serif = 'IM Fell English';
const caps = 'IM Fell English SC';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iPhone and iPad: the plate fills the screen. No status bar (a swipe
  // down from the top shows it for a moment), and the home bar fades
  // until the bottom edge is touched.
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  // The loading screen shows at once; the app starts up behind it.
  runApp(BirdsongApp(boot: AppState.create()));
}

ThemeData birdsongTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: ink, surface: paper).copyWith(
    primary: ink,
    onPrimary: paper,
    primaryContainer: paperDeep,
    onPrimaryContainer: ink,
    secondary: sepia,
    onSecondary: paper,
    secondaryContainer: paperDeep,
    onSecondaryContainer: ink,
    tertiary: madder,
    onTertiary: paper,
    error: madder,
    onError: paper,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: sepia,
    outline: rule,
    outlineVariant: rule,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: paper,
    surfaceContainerLow: paper,
    surfaceContainer: paperDeep,
    surfaceContainerHigh: paperDeep,
    surfaceContainerHighest: paperDeep,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true).textTheme
      .apply(fontFamily: serif);
  // IM Fell has one weight; let it stand rather than be faked bold.
  TextStyle? heading(TextStyle? t, double spacing) =>
      t?.copyWith(fontFamily: caps, fontWeight: FontWeight.w400, letterSpacing: spacing);
  TextStyle? plain(TextStyle? t) => t?.copyWith(fontWeight: FontWeight.w400);
  final text = base.copyWith(
    displayLarge: plain(base.displayLarge),
    displayMedium: plain(base.displayMedium),
    displaySmall: plain(base.displaySmall),
    headlineLarge: heading(base.headlineLarge, 1.2),
    headlineMedium: heading(base.headlineMedium, 1.1),
    headlineSmall: heading(base.headlineSmall, 1.0),
    titleLarge: heading(base.titleLarge, 0.8),
    titleMedium: heading(base.titleMedium, 0.6),
    titleSmall: heading(base.titleSmall, 0.5),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 17),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 16),
    bodySmall: base.bodySmall?.copyWith(fontSize: 13.5),
    labelLarge: plain(base.labelLarge)?.copyWith(fontSize: 15.5),
    labelMedium: plain(base.labelMedium),
    labelSmall: plain(base.labelSmall),
  );
  final hoverFill = ink.withValues(alpha: 0.08);
  final pressFill = ink.withValues(alpha: 0.12);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: serif,
    textTheme: text,
    scaffoldBackgroundColor: paper,
    hoverColor: hoverFill,
    highlightColor: pressFill,
    splashColor: ink.withValues(alpha: 0.10),
    iconTheme: const IconThemeData(color: ink, weight: 300, opticalSize: 24, grade: 0, fill: 0),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: ink,
        hoverColor: hoverFill,
        highlightColor: pressFill,
        focusColor: hoverFill,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: paper,
        disabledBackgroundColor: rule.withValues(alpha: 0.45),
        disabledForegroundColor: sepia.withValues(alpha: 0.7),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: caps, fontSize: 14, letterSpacing: 0.6, fontWeight: FontWeight.w400),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: paperDeep.withValues(alpha: 0.55),
        foregroundColor: ink,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: caps, fontSize: 13.5, letterSpacing: 0.5, fontWeight: FontWeight.w400),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return pressFill;
          if (states.contains(WidgetState.hovered)) return hoverFill;
          return null;
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: caps, fontSize: 13.5, letterSpacing: 0.5, fontWeight: FontWeight.w400),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return pressFill;
          if (states.contains(WidgetState.hovered)) return hoverFill;
          return null;
        }),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return sepia.withValues(alpha: 0.35);
        return states.contains(WidgetState.selected) ? paper : sepia;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return paperDeep.withValues(alpha: 0.5);
        return states.contains(WidgetState.selected) ? ink : paperDeep;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? ink : rule;
      }),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: ink,
      inactiveTrackColor: rule.withValues(alpha: 0.5),
      thumbColor: ink,
      overlayColor: ink.withValues(alpha: 0.12),
      valueIndicatorColor: ink,
      valueIndicatorTextStyle: const TextStyle(fontFamily: serif, color: paper, fontSize: 13),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return ink;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(paper),
      side: const BorderSide(color: ink, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: rule.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper.withValues(alpha: 0.97),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x382A241C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: rule.withValues(alpha: 0.65)),
      ),
      titleTextStyle: const TextStyle(fontFamily: caps, fontSize: 18, letterSpacing: 0.7, color: ink),
      contentTextStyle: const TextStyle(fontFamily: serif, fontSize: 15.5, height: 1.45, color: ink),
    ),
    cardTheme: CardThemeData(
      color: paperDeep.withValues(alpha: 0.42),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    dividerTheme: DividerThemeData(color: rule.withValues(alpha: 0.55), thickness: 1),
    chipTheme: ChipThemeData(
      backgroundColor: paperDeep.withValues(alpha: 0.65),
      selectedColor: ink,
      deleteIconColor: ink,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(fontFamily: serif, fontSize: 14, color: ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: const TextStyle(fontFamily: serif, color: sepia),
      hintStyle: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, color: sepia.withValues(alpha: 0.7)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: rule.withValues(alpha: 0.85))),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ink, width: 1.6)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: paper.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0x332A241C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: rule.withValues(alpha: 0.65)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      iconTheme: IconThemeData(color: ink, weight: 300, opticalSize: 24, grade: 0, fill: 0),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
  );
}

class BirdsongApp extends StatelessWidget {
  const BirdsongApp({super.key, required this.boot});

  final Future<AppState> boot;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'birdsongs.ai',
      debugShowCheckedModeBanner: false,
      theme: birdsongTheme(),
      builder: (context, child) => TooltipVisibility(
        visible: false,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Boot(boot: boot),
    );
  }
}
