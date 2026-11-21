import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import 'index_view.dart' show indexColumns;
import 'landmarks.dart';

/// "Passed on the way", above the map when the map's extras are on and the
/// walk passed something: the heading between two rules, as the Index of
/// Species has it, and what the walk went by in centred columns of 16rem,
/// most particular first. On a phone ([narrow]) the first three, and "and
/// N more". Selecting the heading (or "more") shows the whole list in a
/// box; selecting a line opens its page: its Wikipedia article or Historic
/// England's list entry, else a web search for it.
class PassedView extends StatelessWidget {
  const PassedView({super.key, required this.lookup, required this.width, this.fit = false, this.narrow = false});

  final LandmarkLookup lookup;
  final double width;

  /// Fitted on one screen: smaller and closer, as the index.
  final bool fit;
  final bool narrow;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lookup,
        builder: (context, _) {
          final passed = lookup.walk?.passed ?? const <Passed>[];
          if (passed.isEmpty) return const SizedBox.shrink();
          final shown = narrow ? passed.take(3).toList() : passed;
          final more = passed.length - shown.length;
          return Padding(
            padding: EdgeInsets.only(bottom: fit ? 8 : 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PassedHeading(fit: fit, onTap: () => showPassed(context, passed)),
                SizedBox(height: fit ? 8 : 14),
                PassedColumns(passed: shown, width: width, fit: fit, narrow: narrow),
                if (more > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Semantics(
                      button: true,
                      child: InkWell(
                        onTap: () => showPassed(context, passed),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text('and $more more',
                              style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14, color: sepia)),
                        ),
                      ),
                    ),
                  ),
                if (lookup.walk!.unreached.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text("Couldn't reach: ${lookup.walk!.unreached.join(', ')}.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 12.8, color: sepia)),
                  ),
              ],
            ),
          );
        },
      );
}

/// —— Passed on the way ——, between two rules as the index's heading.
class PassedHeading extends StatelessWidget {
  const PassedHeading({super.key, this.fit = false, this.onTap});

  final bool fit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = fit ? 16.0 : 20.0;
    const line = SizedBox(width: 56, height: 1, child: ColoredBox(color: rule));
    const space = SizedBox(width: 14.4);
    return Center(
      child: Semantics(
        button: onTap != null,
        hint: onTap != null ? 'Show everything passed' : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              line,
              space,
              Flexible(
                child: Text('Passed on the way',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: caps, fontSize: size, letterSpacing: size * .06, height: 1.5, color: ink)),
              ),
              space,
              line,
            ]),
          ),
        ),
      ),
    );
  }
}

/// The lines in centred columns, as the index sets its own.
class PassedColumns extends StatelessWidget {
  const PassedColumns({super.key, required this.passed, required this.width, this.fit = false, this.narrow = false});

  final List<Passed> passed;
  final double width;
  final bool fit;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final colWidth = fit ? 176.0 : 256.0, gap = fit ? 25.6 : 41.6;
    final cols = indexColumns(passed.length, width, colWidth, gap);
    final each = math.min(colWidth, width);
    final size = fit ? 13.44 : (narrow ? 16.0 : 17.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < cols.columns; c++) ...[
          if (c > 0) SizedBox(width: gap),
          SizedBox(
            width: each,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in passed.skip(c * cols.perColumn).take(cols.perColumn)) _Line(p, size: size),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The whole list, in a box over the plate.
Future<void> showPassed(BuildContext context, List<Passed> passed) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x55000000),
      builder: (context) => Dialog(
        backgroundColor: paper,
        surfaceTintColor: paper,
        shape: const RoundedRectangleBorder(),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth - 48;
            return Stack(children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const PassedHeading(),
                  const SizedBox(height: 18),
                  PassedColumns(passed: passed, width: w, narrow: w < 400),
                ]),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20, color: sepia),
                ),
              ),
            ]);
          }),
        ),
      ),
    );

class _Line extends StatefulWidget {
  const _Line(this.p, {required this.size});

  final Passed p;
  final double size;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p, size = widget.size;
    final text = Text.rich(TextSpan(style: TextStyle(fontFamily: serif, fontSize: size, height: 1.4, color: ink), children: [
      TextSpan(
          text: p.name,
          style: TextStyle(color: _hover ? madder : ink, decoration: _hover ? TextDecoration.underline : null)),
      const TextSpan(text: ' '),
      TextSpan(text: p.about, style: TextStyle(color: sepia, fontStyle: FontStyle.italic, fontSize: size * .85)),
      TextSpan(
          text: ' ${p.at != null ? '${p.metres.round()} m' : 'walked through'}',
          style: TextStyle(color: sepia, fontSize: size * .8)),
    ]));
    return Semantics(
      button: true,
      link: true,
      hint: p.link != null ? 'Open its page' : 'Search for it',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => launchUrl(p.page, mode: LaunchMode.externalApplication),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 2.4), child: text),
        ),
      ),
    );
  }
}
