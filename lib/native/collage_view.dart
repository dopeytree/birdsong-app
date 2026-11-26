import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../main.dart' show ink, madder, paper, rule, sepia, serif;
import 'collage_layout.dart';
import 'plate_library.dart';

/// One creature on the collage.
class CollageBird {
  const CollageBird(this.sci, this.common, this.count, this.last);

  final String sci;
  final String common;
  final int count;
  final DateTime? last;
}

/// "1 call", "12 calls", as the web plate says it.
String calls(int n) => n == 1 ? '1 call' : '$n calls';

/// The web plate's collage and everything it does, in Flutter. Each line
/// here is a rule of the page's stylesheet or script (assets/web/index.html):
///
/// - packing and sizes: layout() (collage_layout.dart)
/// - a figure fades in over 0.9 s, the first plateful staggered 28 ms apart
///   (.bird, .bird.in, transitionDelay)
/// - it moves and resizes over 0.7 s on cubic-bezier(.2,.7,.2,1)
/// - under the pointer it grows by 6% about a point 60% down, over 0.25 s,
///   and comes to the front (.bird:hover)
/// - a label follows the pointer: name, scientific name, calls (#tip)
/// - the creature heard last carries a madder dot over its centre or below
///   it, which grows by half under the pointer; or the rest fade to 60%
///   (.bird.newest::after, mark-below, mark-fade)
/// - one being heard right now glows, and its dot breathes out a ring, every
///   1.6 s; held still when the system asks for less motion (.bird.live)
/// - a creature with no plate is its name in an oval (.bird>span)
/// - figures lower down overlap those above; a name sits over them all
class CollageView extends StatefulWidget {
  const CollageView({
    super.key,
    required this.birds,
    required this.art,
    required this.size,
    required this.sizeBy,
    required this.markAt,
    required this.newest,
    required this.live,
    required this.onOpen,
    this.showHoverInfo = false,
    this.showAllNameTickets = false,
    this.onDragHold,
    this.resetAfter = const Duration(seconds: 10),
  });

  /// The creatures to draw, most heard first. Only those in [art].
  final List<CollageBird> birds;

  /// Each one's plate; null for none.
  final Map<String, PlateArt?> art;
  final Size size;

  /// 'calls', 'time' or 'equal'.
  final String sizeBy;

  /// 'centre', 'below', 'fade' or 'none'.
  final String markAt;

  /// The creature heard last, which carries the mark; it may be one that
  /// is not on the plate.
  final String? newest;

  /// Scientific names being heard right now.
  final Set<String> live;
  final ValueChanged<CollageBird> onOpen;

  /// Whether hovering over a bird shows the info ticket (off by default to
  /// encourage clicking to open the bird card, matching touch devices).
  final bool showHoverInfo;

  /// Whether all birds in the collage show a name ticket (off by default; only
  /// the centred bird shows the madder ticket with a + symbol).
  final bool showAllNameTickets;

  /// Called when the user begins/ends dragging the collage so the outer scroll
  /// view can pause while dragging.
  final ValueChanged<bool>? onDragHold;

  /// How long after the last drag before the collage glides back to default.
  final Duration resetAfter;

  @override
  State<CollageView> createState() => _CollageViewState();
}

class _CollageViewState extends State<CollageView> {
  String? _hover;
  Offset _pointer = Offset.zero;

  /// Purely visual virtual focus: while the user drags across the collage, the
  /// bird under their finger/pointer is given the top weight so [layoutCollage]
  /// glides it into the centre as the largest bird (nothing saved to disk).
  /// Resets to null after [widget.resetAfter] with no drag.
  String? _focusedSci;
  List<CollagePlace> _lastPlaces = const [];
  DateTime _lastSwitch = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _resetTimer;

  // The first plateful comes in one after another; later arrivals at once.
  bool _first = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _first = false);
  }

  @override
  void didUpdateWidget(CollageView old) {
    super.didUpdateWidget(old);
    if (old.sizeBy != widget.sizeBy || old.size != widget.size) {
      _resetTimer?.cancel();
      _focusedSci = null;
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    if (_focusedSci == null) return;
    _resetTimer = Timer(widget.resetAfter, () {
      if (!mounted) return;
      setState(() => _focusedSci = null);
    });
  }

  void _focusAt(Offset local, {bool force = false}) {
    CollagePlace? hit;
    // Prefer a direct hit on a bird's current box (checking top-most first).
    for (var i = _lastPlaces.length - 1; i >= 0; i--) {
      if (_lastPlaces[i].rect.contains(local)) {
        hit = _lastPlaces[i];
        break;
      }
    }
    if (hit == null || hit.id == _focusedSci) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSwitch) < const Duration(milliseconds: 280)) return;
    _lastSwitch = now;
    setState(() => _focusedSci = hit!.id);
    _scheduleReset();
  }

  void _onPanStart(DragStartDetails d) {
    _resetTimer?.cancel();
    widget.onDragHold?.call(true);
    _focusAt(d.localPosition, force: true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _focusAt(d.localPosition);
  }

  void _onPanEnd() {
    widget.onDragHold?.call(false);
    _scheduleReset();
  }

  @override
  Widget build(BuildContext context) {
    final birds = widget.birds, art = widget.art;
    if (birds.isEmpty) return SizedBox.fromSize(size: widget.size);
    // Sized by time it is the order that counts, not the gap: a morning's
    // birds would otherwise come out all of a size.
    final byTime = [...birds]..sort((a, b) => (a.last ?? DateTime(0)).compareTo(b.last ?? DateTime(0)));
    double baseWeight(CollageBird b) => switch (widget.sizeBy) {
          'equal' => 1,
          'time' => (byTime.indexOf(b) + 1).toDouble(),
          _ => b.count.toDouble(),
        };
    final maxWeight = birds.map(baseWeight).reduce(math.max);
    // Purely visual virtual boost for the dragged/focused bird so layoutCollage
    // promotes it to the centre at hero size using the exact standard layout.
    double weight(CollageBird b) {
      if (_focusedSci != null && b.sci == _focusedSci) {
        return widget.sizeBy == 'equal' ? 3.0 : maxWeight * 1.15;
      }
      return baseWeight(b);
    }

    final items = [
      for (final b in birds)
        CollageItem(
          b.sci,
          weight: weight(b),
          aspect: art[b.sci]?.aspect ?? 1.7,
          blank: art[b.sci] == null && b.sci != _focusedSci,
        )
    ];
    final useEvenGrid = widget.sizeBy == 'equal' && _focusedSci == null;
    final places = useEvenGrid ? layoutEvenGrid(items, widget.size) : layoutCollage(items, widget.size);
    _lastPlaces = places;
    // layoutCollage puts the largest / hero bird first, dead centre;
    // in No pecking order (even grid), no bird is singled out as hero.
    final centerSci = useEvenGrid || places.isEmpty ? null : places.first.id;
    final bird = {for (final b in birds) b.sci: b};
    final newest = widget.markAt == 'none' ? null : widget.newest;
    // has-newest: the rest only stand back when the latest is on the plate
    final fadeRest = widget.markAt == 'fade' && bird.containsKey(newest);

    // Stacking: by how far down it sits, a name (z 4) over the figures, the
    // one under the pointer (z 5) over everything.
    int z(CollagePlace p) => p.id == _hover ? 1000 : (art[p.id] == null ? 900 : p.order);
    final order = [...places]..sort((a, b) => z(a).compareTo(z(b)));
    final at = {for (var i = 0; i < places.length; i++) places[i].id: i};
    final tipFor = widget.showHoverInfo && _hover != null ? bird[_hover] : null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (_) => _onPanEnd(),
      onPanCancel: _onPanEnd,
      child: SizedBox.fromSize(
        size: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final p in order)
              AnimatedPositioned(
                key: ValueKey(p.id),
                duration: const Duration(milliseconds: 700),
                curve: const Cubic(.2, .7, .2, 1),
                left: p.rect.left,
                top: p.rect.top,
                width: p.rect.width,
                height: p.rect.height,
                child: _Bird(
                  bird: bird[p.id]!,
                  art: art[p.id],
                  width: p.rect.width,
                  delay: _first ? Duration(milliseconds: 28 * at[p.id]!) : Duration.zero,
                  hovered: _hover == p.id,
                  isCenter: p.id == centerSci,
                  showNameTicket: p.id == centerSci || widget.showAllNameTickets,
                  newest: p.id == newest,
                  markBelow: widget.markAt == 'below',
                  showDot: widget.markAt == 'centre' || widget.markAt == 'below',
                  faded: fadeRest && p.id != newest,
                  live: widget.live.contains(p.id),
                  onHover: (where) => setState(() {
                    _hover = where == null ? (_hover == p.id ? null : _hover) : p.id;
                    if (where != null) _pointer = p.rect.topLeft + where;
                  }),
                  onTap: () => widget.onOpen(bird[p.id]!),
                  onLongPress: () => widget.onOpen(bird[p.id]!),
                ),
              ),
            // The label that follows the pointer.
            Positioned(
              left: _pointer.dx,
              top: _pointer.dy - 18,
              child: IgnorePointer(
                child: FractionalTranslation(
                  translation: const Offset(-.5, -1),
                  child: AnimatedOpacity(
                    opacity: tipFor == null ? 0 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: tipFor == null ? const SizedBox() : _Tip(tipFor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One figure: its plate (or its name in an oval), with the page's fade-in,
/// growth under the pointer, latest-heard dot and being-heard glow.
class _Bird extends StatefulWidget {
  const _Bird({
    required this.bird,
    required this.art,
    required this.width,
    required this.delay,
    required this.hovered,
    required this.isCenter,
    required this.showNameTicket,
    required this.newest,
    required this.markBelow,
    required this.showDot,
    required this.faded,
    required this.live,
    required this.onHover,
    required this.onTap,
    required this.onLongPress,
  });

  final CollageBird bird;
  final PlateArt? art;
  final double width;
  final Duration delay;
  final bool hovered;
  final bool isCenter;
  final bool showNameTicket;
  final bool newest;
  final bool markBelow;
  final bool showDot;
  final bool faded;
  final bool live;

  /// Where the pointer is inside the figure, or null when it has left.
  final ValueChanged<Offset?> onHover;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_Bird> createState() => _BirdState();
}

class _BirdState extends State<_Bird> with TickerProviderStateMixin {
  // opacity 0 to 1 over 0.9 s (the page's default ease), after [delay]
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<double> _fade = CurvedAnimation(parent: _in, curve: Curves.ease);
  // the 1.6 s breath of a creature being heard
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _in.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _in.forward();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _breathe();
  }

  @override
  void didUpdateWidget(_Bird old) {
    super.didUpdateWidget(old);
    if (old.live != widget.live) _breathe();
  }

  void _breathe() {
    final still = MediaQuery.disableAnimationsOf(context);
    if (widget.live && !still) {
      if (!_breath.isAnimating) _breath.repeat();
    } else {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.art, b = widget.bird;
    final still = MediaQuery.disableAnimationsOf(context);
    Widget figure = art == null
        ? _NameOval(b.common)
        : PlateImage(art: art, width: widget.width);
    if (widget.live && art != null) {
      // filter: drop-shadow(0 0 .8rem rgba(140,59,42,.7)) at the middle of
      // the breath: a blurred madder copy of the figure behind it.
      figure = Stack(fit: StackFit.expand, children: [
        AnimatedBuilder(
          animation: _breath,
          builder: (context, child) => Opacity(
            opacity: still ? .6 : .7 * math.sin(math.pi * Curves.easeInOut.transform(_breath.value)),
            child: child,
          ),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7, tileMode: TileMode.decal),
            child: PlateImage(art: art, width: widget.width, silhouette: madder),
          ),
        ),
        figure,
      ]);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (e) => widget.onHover(e.localPosition),
      onExit: (_) => widget.onHover(null),
      child: Semantics(
        button: true,
        label: '${b.common}, ${calls(b.count)}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: FadeTransition(
            opacity: _fade,
            child: AnimatedOpacity(
              // mark-fade: the rest stand back to 60%
              opacity: widget.faded ? .6 : 1,
              duration: const Duration(milliseconds: 900),
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    scale: widget.hovered ? 1.06 : 1,
                    alignment: const Alignment(0, .2), // transform-origin: 50% 60%
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: figure,
                  ),
                  if (widget.showNameTicket && art != null)
                    Align(
                      alignment: const Alignment(0, 0.82),
                      child: IgnorePointer(
                        child: Container(
                          constraints: BoxConstraints(maxWidth: math.max(54, widget.width - 10)),
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.isCenter ? 8 : 6,
                            vertical: widget.isCenter ? 2.5 : 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: paper.withValues(alpha: 0.86),
                            border: Border.all(color: rule, width: 0.85),
                            boxShadow: const [BoxShadow(color: Color(0x283C280A), blurRadius: 4)],
                          ),
                          child: Text(
                            b.common,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: serif,
                              fontStyle: FontStyle.italic,
                              fontSize: widget.isCenter ? 13.5 : (widget.width < 90 ? 10.5 : 12),
                              height: 1.15,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.newest && widget.showDot)
                    Align(
                      // over its centre, or on its lower edge (top:100%, -70%)
                      alignment: widget.markBelow ? Alignment.bottomCenter : Alignment.center,
                      child: Transform.translate(
                        offset: widget.markBelow ? const Offset(0, 8 * .3) : Offset.zero,
                        child: AnimatedScale(
                          scale: widget.hovered ? 1.5 : 1,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          child: _Dot(breath: widget.live && !still ? _breath : null),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The latest-heard dot: half a rem of madder with a paper glow. While its
/// creature is being heard it breathes out a ring (bsRing).
class _Dot extends StatelessWidget {
  const _Dot({this.breath});

  final Animation<double>? breath;

  @override
  Widget build(BuildContext context) {
    const size = 8.0; // .5rem
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: madder.withValues(alpha: .9),
        boxShadow: const [BoxShadow(color: paper, blurRadius: 4)],
      ),
    );
    final breath = this.breath;
    if (breath == null) return IgnorePointer(child: dot);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: breath,
        builder: (context, child) {
          final t = Curves.easeOut.transform(breath.value);
          return DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
              // box-shadow: 0 0 0 0 rgba(140,59,42,.6) to 0 0 0 .8rem transparent
              BoxShadow(color: madder.withValues(alpha: .6 * (1 - t)), spreadRadius: 12.8 * t),
            ]),
            child: child,
          );
        },
        child: dot,
      ),
    );
  }
}

/// A creature with no plate: its name in an oval, in italics.
class _NameOval extends StatelessWidget {
  const _NameOval(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: rule),
            borderRadius: BorderRadius.all(Radius.elliptical(box.maxWidth / 2, box.maxHeight / 2)),
          ),
          child: Text(name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: serif,
                  fontStyle: FontStyle.italic,
                  // font-size: clamp(.6rem, 1.1vw, .9rem)
                  fontSize: (MediaQuery.sizeOf(context).width * .011).clamp(9.6, 14.4),
                  height: 1.15,
                  color: sepia)),
        ),
      );
}

/// The label under the pointer: a ruled ticket with the name, the
/// scientific name and the calls (#tip).
class _Tip extends StatelessWidget {
  const _Tip(this.bird);

  final CollageBird bird;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 256),
        // box-shadow: 0 0 0 3px paper, 0 0 0 4px rule, 0 6px 18px
        decoration: const BoxDecoration(color: paper, boxShadow: [
          BoxShadow(color: paper, spreadRadius: 3),
          BoxShadow(color: rule, spreadRadius: 4),
          BoxShadow(color: Color(0x2E3C280A), offset: Offset(0, 6), blurRadius: 18),
        ]),
        foregroundDecoration: BoxDecoration(border: Border.all(color: rule)),
        padding: const EdgeInsets.fromLTRB(12.8, 7.2, 12.8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bird.common,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: serif, fontSize: 16.8, height: 1.25, color: ink)),
            Text(bird.sci,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14.4, height: 1.25, color: sepia)),
            Text(calls(bird.count),
                style: const TextStyle(fontFamily: serif, fontSize: 14.4, height: 1.25, color: madder)),
          ],
        ),
      );
}

/// A plate drawn to fit. Cut-outs (ready-made, or cut on this device) and
/// tinted plates are multiplied by the paper colour, as the page's paperTint
/// filter does, so a pale edge melts into the page. [silhouette] draws its shape in one colour
/// instead (for the glow).
class PlateImage extends StatelessWidget {
  const PlateImage({super.key, required this.art, required this.width, this.silhouette});

  final PlateArt art;
  final double width;
  final Color? silhouette;

  @override
  Widget build(BuildContext context) {
    final shape = silhouette;
    final tint = art.tint || art.cut || art.from.ready;
    return Image.file(
      art.file,
      fit: BoxFit.contain,
      // decode no larger than it is drawn
      cacheWidth: math.max(1, (width * MediaQuery.devicePixelRatioOf(context)).round()),
      // modulate multiplies colour and alpha alike, so a cut-out stays cut out
      color: shape ?? (tint ? paper : null),
      colorBlendMode: shape != null ? BlendMode.srcIn : (tint ? BlendMode.modulate : null),
      gaplessPlayback: true,
      errorBuilder: (context, _, __) => const SizedBox(),
    );
  }
}

/// While the plates are gathered: the page's words and its hairline rule,
/// which fills as each plate arrives, a slow sheen travelling along it
/// (#status, #load).
class PlateStatus extends StatefulWidget {
  const PlateStatus({super.key, required this.done, required this.of});

  final int done;
  final int of;

  @override
  State<PlateStatus> createState() => _PlateStatusState();
}

class _PlateStatusState extends State<PlateStatus> with SingleTickerProviderStateMixin {
  late final AnimationController _along =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _along.stop();
    } else if (!_along.isAnimating) {
      _along.repeat();
    }
  }

  @override
  void dispose() {
    _along.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(208.0, MediaQuery.sizeOf(context).width * .52);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Preparing the plate… ${widget.done} of ${widget.of}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 18.4, color: sepia)),
        const SizedBox(height: 14.4),
        SizedBox(
          width: width,
          height: 2,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: rule),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.of == 0 ? 0 : widget.done / widget.of),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  builder: (context, p, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: p.clamp(0.0, 1.0),
                    child: const ColoredBox(color: madder),
                  ),
                ),
                AnimatedBuilder(
                  animation: _along,
                  builder: (context, child) => Positioned(
                    left: (-.34 + 1.34 * _along.value) * width,
                    top: 0,
                    bottom: 0,
                    width: .34 * width,
                    child: child!,
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0x008C3B2A), Color(0x808C3B2A), Color(0x008C3B2A)]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The page's paper: its colour, a vignette (an ellipse centred 40% down,
/// clear to 55% of the way out, then to rgba(120,95,50,.13) at the far
/// corner) and a fine brown grain. Painted once for a size.
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _PaperPainter())),
          child,
        ],
      );
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = paper);
    // Grain: the same specks every time, at the strength of the page's
    // noise (alpha .07 of a dark brown).
    final rnd = math.Random(11);
    final speck = Paint()..color = const Color(0x12594526);
    final n = (size.width * size.height / 70).round().clamp(0, 24000);
    for (var i = 0; i < n; i++) {
      canvas.drawRect(
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height) & const Size(1, 1), speck);
    }
    // The vignette, drawn in a unit square so the circle becomes the
    // page's ellipse. The far corner is (.5, .6) away.
    canvas.save();
    canvas.translate(size.width / 2, size.height * .4);
    canvas.scale(size.width, size.height);
    canvas.drawRect(
      const Rect.fromLTRB(-.5, -.4, .5, .6),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          math.sqrt(.5 * .5 + .6 * .6),
          const [Color(0x00785F32), Color(0x00785F32), Color(0x21785F32)],
          const [0, .55, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaperPainter old) => false;
}

/// Pinch to zoom the collage, on touch screens, as the app does on the web
/// plate (assets/app/plate-extras.js): two fingers zoom about their
/// midpoint up to four times, one finger pans once zoomed in, a double tap
/// goes back, and letting go below 1.05 goes back too. A pinch never opens a
/// creature's card (the zoom wins over the tap); a plain tap still does. A
/// new layout starts unzoomed.
///
/// [onHold] says when the page around it should stop scrolling: while two
/// fingers are on the collage, and while it is zoomed in, so one finger
/// pans the birds rather than the page.
class ZoomableCollage extends StatefulWidget {
  const ZoomableCollage({super.key, required this.size, required this.onHold, required this.child});

  final Size size;
  final ValueChanged<bool> onHold;
  final Widget child;

  /// Only where fingers are the pointer, as on the web plate.
  static bool get touch =>
      defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;

  @override
  State<ZoomableCollage> createState() => _ZoomableCollageState();
}

class _ZoomableCollageState extends State<ZoomableCollage> {
  final _view = TransformationController();
  final Set<int> _fingers = {};
  bool _zoomed = false, _held = false;

  double get _scale => _view.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _view.addListener(_changed);
  }

  @override
  void didUpdateWidget(ZoomableCollage old) {
    super.didUpdateWidget(old);
    // not now, in the middle of a build: the page is told, and may set state
    if (old.size != widget.size) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reset();
      });
    }
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  void _changed() {
    final zoomed = _scale > 1.001;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    _tell();
  }

  void _tell() {
    final held = _zoomed || _fingers.length >= 2;
    if (held == _held) return;
    _held = held;
    widget.onHold(held);
  }

  void _reset() => _view.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    if (!ZoomableCollage.touch) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _fingers.add(e.pointer);
        _tell();
      },
      onPointerUp: (e) {
        _fingers.remove(e.pointer);
        _tell();
      },
      onPointerCancel: (e) {
        _fingers.remove(e.pointer);
        _tell();
      },
      child: GestureDetector(
        // only once zoomed in: otherwise a tap on a bird would wait to see
        // whether a second one follows
        onDoubleTap: _zoomed ? _reset : null,
        child: InteractiveViewer(
          transformationController: _view,
          minScale: 1,
          maxScale: 4,
          panEnabled: _zoomed,
          clipBehavior: Clip.hardEdge,
          onInteractionEnd: (_) {
            if (_scale < 1.05) _reset();
          },
          child: SizedBox.fromSize(size: widget.size, child: widget.child),
        ),
      ),
    );
  }
}
