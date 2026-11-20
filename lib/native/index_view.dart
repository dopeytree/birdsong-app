import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart' show caps, ink, madder, rule, sepia, serif;

/// One line of the index.
class IndexEntry {
  const IndexEntry(this.sci, this.common, this.count, {this.noPlate = false});

  final String sci;
  final String common;
  final int count;

  /// Looked for and not found: the line says "(no plate)".
  final bool noPlate;
}

/// How the page's index is set out (its sizeIndex()): columns of [colWidth]
/// with [gap] between, as many as fit in [avail], but no more than the list
/// really fills when each column is the same height. A list of seven with
/// room for six becomes four columns of two. Returns the columns used and
/// the lines in each.
({int columns, int perColumn}) indexColumns(int n, double avail, double colWidth, double gap) {
  if (n <= 0) return (columns: 0, perColumn: 0);
  final room = math.max(1, ((avail + gap) / (colWidth + gap)).floor());
  final per = (n / room).ceil();
  return (columns: (n / per).ceil(), perColumn: per);
}

/// 1234 as "1,234", as the page's toLocaleString does.
String thousands(int n) {
  final s = n.abs().toString(), out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// The web plate's "Index of species" and what the app adds to it, in
/// Flutter. From assets/web/index.html (h2, #index, body.fit) and the app's
/// plate-extras.js and injected styles (.bsIx, .bsIxArrow, .bsStep):
///
/// - the heading in small capitals between two short rules, centred
/// - tap the heading to fold the list away and back; a small arrow below
///   the list (to fold) or above the heading (to unfold) does the same
/// - with more than one session, ‹ and › at the outer ends step between
///   them; one with nowhere to go keeps its place but is not drawn
/// - the list runs down columns of 16rem (11rem fitted on one screen), no
///   wider than the columns it fills, centred
/// - a line is the name, a dotted leader and the count in madder old-style
///   figures; the name underlines under the pointer; its scientific name is
///   the tooltip; "(no plate)" after a name with no picture
/// - the latest heard has its name in madder
/// - fitted on one screen everything is set smaller and closer
class IndexView extends StatelessWidget {
  const IndexView({
    super.key,
    required this.entries,
    required this.width,
    required this.fit,
    required this.narrow,
    required this.folded,
    required this.onFold,
    this.foldable = true,
    required this.newest,
    required this.steps,
    required this.canPrev,
    required this.canNext,
    required this.onStep,
    required this.onOpen,
  });

  final List<IndexEntry> entries;

  /// The room across, inside the section's padding.
  final double width;
  final bool fit;

  /// A screen of 720 or less: the page's type drops from 18 to 16.
  final bool narrow;
  final bool folded;
  final VoidCallback onFold;

  /// False for the index alone (view c): nothing to fold it away to, so no
  /// fold arrows and the heading is only a heading.
  final bool foldable;

  /// The latest heard, when it is to be marked.
  final String? newest;

  /// Whether there are sessions to step between.
  final bool steps;
  final bool canPrev;
  final bool canNext;
  final ValueChanged<int> onStep;
  final ValueChanged<IndexEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    // rem is 16 throughout the page
    final colWidth = fit ? 176.0 : 256.0, gap = fit ? 25.6 : 41.6;
    final fontSize = fit ? 13.44 : (narrow ? 16.0 : 18.0);
    final lineHeight = fit ? 1.35 : 1.5;
    final cols = indexColumns(entries.length, width, colWidth, gap);
    // one column on a screen narrower than a column takes what there is
    final each = math.min(colWidth, width);
    const arrow = TextStyle(fontFamily: serif, fontSize: 18, height: 1, color: sepia);
    Widget fold(String glyph, EdgeInsets margin) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onFold,
          child: ExcludeSemantics(
            child: Container(
              width: double.infinity,
              margin: margin,
              alignment: Alignment.center,
              child: Opacity(opacity: .75, child: Text(glyph, style: arrow)),
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (foldable && folded) fold('⌃', const EdgeInsets.only(bottom: 1.6)),
        _heading(),
        SizedBox(height: fit ? 13.6 : 25.6),
        if (!folded) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < cols.columns; c++) ...[
                if (c > 0) SizedBox(width: gap),
                SizedBox(
                  width: each,
                  child: Column(
                    children: [
                      for (final e in entries.skip(c * cols.perColumn).take(cols.perColumn))
                        _Line(
                          entry: e,
                          newest: e.sci == newest,
                          width: each,
                          fontSize: fontSize,
                          lineHeight: lineHeight,
                          onTap: () => onOpen(e),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (foldable) fold('⌄', const EdgeInsets.only(top: 4.8)),
        ],
      ],
    );
  }

  /// ‹ —— Index of species —— ›
  Widget _heading() {
    Widget step(int by, String glyph, String label, bool on) => Visibility(
          visible: on,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Semantics(
            button: true,
            label: label,
            child: InkResponse(
              radius: 22,
              onTap: () => onStep(by),
              child: Padding(
                // a finger's worth of room about a small glyph
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ExcludeSemantics(
                  child: Text(glyph,
                      style: TextStyle(
                          fontFamily: serif, fontSize: (fit ? 16 : 20) * 1.25, height: 1, color: sepia)),
                ),
              ),
            ),
          ),
        );
    const line = SizedBox(width: 56, height: 1, child: ColoredBox(color: rule));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (steps) step(-1, '‹', 'Earlier session', canPrev),
        Flexible(
          child: Semantics(
            button: foldable,
            expanded: foldable ? !folded : null,
            child: InkWell(
              onTap: foldable ? onFold : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  line,
                  const SizedBox(width: 14.4),
                  Flexible(
                    child: Text('Index of species',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: caps,
                            fontSize: fit ? 16 : 20,
                            letterSpacing: (fit ? 16 : 20) * .06,
                            height: 1.5,
                            color: ink)),
                  ),
                  const SizedBox(width: 14.4),
                  line,
                ],
              ),
            ),
          ),
        ),
        if (steps) step(1, '›', 'Later session', canNext),
      ],
    );
  }
}

/// A line of the index: name, dotted leader, count.
class _Line extends StatefulWidget {
  const _Line({
    required this.entry,
    required this.newest,
    required this.width,
    required this.fontSize,
    required this.lineHeight,
    required this.onTap,
  });

  final IndexEntry entry;
  final bool newest;

  /// The column's width: a long name wraps before it crowds out the count.
  final double width;
  final double fontSize;
  final double lineHeight;
  final VoidCallback onTap;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry, size = widget.fontSize;
    final name = TextStyle(
      fontFamily: serif,
      fontSize: size,
      height: widget.lineHeight,
      color: widget.newest ? madder : ink,
      decoration: _over ? TextDecoration.underline : TextDecoration.none,
      decorationColor: rule,
    );
    return Tooltip(
      message: e.sci,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: Semantics(
          button: true,
          label: '${e.common}, ${thousands(e.count)}${e.noPlate ? ', no plate' : ''}',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.3), // .08rem
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: widget.width * .78),
                    child: Text.rich(
                      TextSpan(text: e.common, children: [
                        if (e.noPlate)
                          const TextSpan(
                              text: ' (no plate)',
                              style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13.6,
                                  color: sepia,
                                  decoration: TextDecoration.none)),
                      ]),
                      style: name,
                    ),
                  ),
                  const SizedBox(width: 6.4),
                  // the leader: dots along a line a quarter of an em above
                  // the baseline, which sits about the middle of the line
                  Expanded(
                    child: CustomPaint(
                      size: Size(double.infinity, size * widget.lineHeight),
                      painter: _Leader(size * widget.lineHeight * .5 + size * .08),
                    ),
                  ),
                  const SizedBox(width: 6.4),
                  Text(thousands(e.count),
                      style: TextStyle(
                          fontFamily: serif,
                          fontSize: size,
                          height: widget.lineHeight,
                          color: madder,
                          fontFeatures: const [FontFeature.oldstyleFigures()])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// border-bottom: 1px dotted, in the rule colour.
class _Leader extends CustomPainter {
  const _Leader(this.y);

  final double y;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = rule;
    for (var x = 0.0; x + 1 <= size.width; x += 2) {
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), dot);
    }
  }

  @override
  bool shouldRepaint(_Leader old) => old.y != y;
}
