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
  final scheme = ColorScheme.fromSeed(seedColor: madder, surface: paper).copyWith(
    primary: madder,
    onPrimary: paper,
    primaryContainer: paperDeep,
    onPrimaryContainer: ink,
    secondary: sepia,
    onSecondary: paper,
    secondaryContainer: madder,
    onSecondaryContainer: paper,
    tertiary: sepia,
    onTertiary: paper,
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
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: serif,
    textTheme: text,
    scaffoldBackgroundColor: paper,
    hoverColor: ink.withValues(alpha: 0.08),
    highlightColor: ink.withValues(alpha: 0.12),
    splashColor: ink.withValues(alpha: 0.10),
    iconTheme: const IconThemeData(color: ink),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: ink,
        hoverColor: ink.withValues(alpha: 0.08),
        highlightColor: ink.withValues(alpha: 0.12),
        focusColor: ink.withValues(alpha: 0.08),
      ),
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
      iconTheme: IconThemeData(color: ink),
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
      title: 'Birdsong',
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
