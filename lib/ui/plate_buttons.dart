import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;

// The plate's own controls, shared by the web plate (plate_view.dart) and
// the Flutter plate (native/native_plate.dart) so both carry the same ones.

/// One action inside [showModernMenu], styled identically to [SpeciesSortBar].
class ModernMenuItem<T> {
  const ModernMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.subtitle,
    this.selected = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? subtitle;
  final bool selected;
}

/// Floating translucent popover menu anchored to [anchorContext], matching
/// the exact rounded frosted-paper card and rounded hover chips of
/// [SpeciesSortBar] (no boxy Material [PopupMenuButton] row highlights).
Future<T?> showModernMenu<T>({
  required BuildContext anchorContext,
  required List<ModernMenuItem<T>> items,
  double minWidth = 176,
}) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return Future.value(null);
  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final screen = overlay.size;
  final openAbove = anchor.center.dy > screen.height * 0.5;
  final alignRight = anchor.center.dx > screen.width * 0.5;
  final origin = Alignment(alignRight ? 1.0 : -1.0, openAbove ? 1.0 : -1.0);

  return showGeneralDialog<T>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: 'Dismiss menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, __) {
      final menu = Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: BoxConstraints(
            minWidth: minWidth,
            maxWidth: math.min(280.0, screen.width - 16),
          ),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: paper.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rule.withValues(alpha: 0.55)),
            boxShadow: const [
              BoxShadow(color: Color(0x262A241C), offset: Offset(0, 4), blurRadius: 16),
            ],
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      hoverColor: ink.withValues(alpha: 0.08),
                      highlightColor: ink.withValues(alpha: 0.12),
                      onTap: () => Navigator.of(dialogContext).pop(item.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.icon, size: 18, color: item.selected ? madder : ink),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: caps,
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                      color: item.selected ? madder : ink,
                                    ),
                                  ),
                                  if (item.subtitle != null && item.subtitle!.isNotEmpty)
                                    Text(
                                      item.subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: serif,
                                        fontStyle: FontStyle.italic,
                                        fontSize: 12,
                                        height: 1.2,
                                        color: sepia,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (item.selected) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.check, size: 16, color: madder),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      final pad = MediaQuery.paddingOf(dialogContext);
      final left = alignRight ? null : math.max(8.0, anchor.left);
      final right = alignRight ? math.max(8.0, screen.width - anchor.right) : null;
      final top = openAbove ? null : math.max(pad.top + 8.0, anchor.bottom + 4.0);
      final bottom = openAbove ? math.max(pad.bottom + 8.0, screen.height - anchor.top + 4.0) : null;
      return Stack(
        children: [
          Positioned(
            left: left,
            right: right,
            top: top,
            bottom: bottom,
            child: menu,
          ),
        ],
      );
    },
    transitionBuilder: (_, anim, __, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curve),
          alignment: origin,
          child: child,
        ),
      );
    },
  );
}

/// A slim paper notification strip along the top of the screen, matching the
/// model update banner's look and placement.
class PlateNote extends StatelessWidget {
  const PlateNote({super.key, required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final message = Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: serif,
        fontStyle: FontStyle.italic,
        fontSize: 16,
        color: ink,
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Material(
            color: paper.withValues(alpha: 0.95),
            elevation: 4,
            shadowColor: const Color(0x382A241C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: rule.withValues(alpha: 0.65)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 6, action == null ? 14 : 6, 6),
              child: action == null
                  ? message
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: message),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: madder,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontFamily: caps,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          onPressed: onAction,
                          child: Text(action!),
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

/// The source, as a two-part pill: Listen here (microphone) | a remote
/// station (sensors). The one on show is filled in madder; a tap on the
/// other switches to it.
class SourcePill extends StatelessWidget {
  const SourcePill({
    super.key,
    required this.listen,
    required this.stationName,
    required this.onListen,
    required this.onRemote,
  });

  /// Each half's width.
  static const half = 40.0;

  /// Its height: a little under the menu icon's 24 plus its own margin,
  /// so it sits with the round buttons rather than over them.
  static const height = 30.0;

  /// The height of the row of round buttons along the top (record, menu):
  /// each sits in a box this tall, its middle level with the others'.
  static const rowHeight = 48.0;

  final bool listen;
  final String? stationName;
  final VoidCallback onListen;
  final VoidCallback onRemote;

  @override
  Widget build(BuildContext context) {
    Widget part(bool on, IconData icon, String tip, VoidCallback tap, BorderRadius r) => Tooltip(
          message: tip,
          child: Semantics(
            button: true,
            selected: on,
            label: tip,
            child: Material(
              color: on ? ink : Colors.transparent,
              borderRadius: r,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: tap,
                hoverColor: ink.withValues(alpha: 0.08),
                highlightColor: ink.withValues(alpha: 0.12),
                child: SizedBox(
                  width: half,
                  height: height,
                  child: Icon(icon, size: 18, color: on ? paper : ink.withValues(alpha: 0.65)),
                ),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: paper.withValues(alpha: 0.85),
        border: Border.all(color: ink.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(height / 2 + 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          part(listen, Icons.mic_none_outlined, 'Listen here & now', onListen,
              const BorderRadius.horizontal(left: Radius.circular(height / 2))),
          part(!listen, Icons.sensors,
              stationName == null ? 'Add a remote station' : 'Remote station: $stationName',
              onRemote, const BorderRadius.horizontal(right: Radius.circular(height / 2))),
        ],
      ),
    );
  }
}

/// Record a new session, or stop the one recording: a black dot when idle,
/// a softly glowing red recording dot while active, a spinner while starting.
class RecordButton extends StatefulWidget {
  const RecordButton({super.key, required this.recording, required this.busy, required this.onTap});

  final bool recording;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> with SingleTickerProviderStateMixin {
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  static const _recRed = Color(0xFFC82820);

  @override
  void initState() {
    super.initState();
    if (widget.recording) _glow.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(RecordButton old) {
    super.didUpdateWidget(old);
    if (widget.recording && !_glow.isAnimating) _glow.repeat(reverse: true);
    if (!widget.recording && _glow.isAnimating) _glow.reset();
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Center(
        child: widget.busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: ink),
              )
            : IconButton(
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                padding: EdgeInsets.zero,
                tooltip: widget.recording ? 'Stop recording' : 'Record a new session',
                onPressed: widget.onTap,
                icon: widget.recording
                    ? AnimatedBuilder(
                        animation: _glow,
                        builder: (context, _) {
                          final g = 0.35 + 0.55 * Curves.easeInOut.transform(_glow.value);
                          return Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _recRed,
                              boxShadow: [
                                BoxShadow(
                                  color: _recRed.withValues(alpha: g),
                                  blurRadius: 10,
                                  spreadRadius: 2.5,
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : const Icon(Icons.fiber_manual_record, size: 17, color: ink),
              ),
      ),
    );
  }
}
