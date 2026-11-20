import 'package:flutter/material.dart';

import '../main.dart' show ink, paper, rule, sepia, serif;

// The plate's own controls, shared by the web plate (plate_view.dart) and
// the Flutter plate (native/native_plate.dart) so both carry the same ones.

/// A short message on paper, ruled like the plate's pop-ups.
class PlateNote extends StatelessWidget {
  const PlateNote({super.key, required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: paper,
      elevation: 3,
      shadowColor: const Color(0x553C280A),
      shape: const RoundedRectangleBorder(side: BorderSide(color: rule)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, action == null ? 16 : 6, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 16, color: ink)),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action!)),
          ],
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
  static const half = 46.0;

  final bool listen;
  final String? stationName;
  final VoidCallback onListen;
  final VoidCallback onRemote;

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    Widget part(bool on, IconData icon, String tip, VoidCallback tap, BorderRadius r) => Tooltip(
          message: tip,
          child: Semantics(
            button: true,
            selected: on,
            label: tip,
            child: InkWell(
              borderRadius: r,
              onTap: tap,
              child: Container(
                width: half,
                height: 36,
                decoration: BoxDecoration(color: on ? red : Colors.transparent, borderRadius: r),
                child: Icon(icon, size: 21, color: on ? paper : sepia.withValues(alpha: 0.7)),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: paper.withValues(alpha: 0.85),
        border: Border.all(color: red.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          part(listen, Icons.mic_none_outlined, 'Listen here & now', onListen,
              const BorderRadius.horizontal(left: Radius.circular(18))),
          part(!listen, Icons.sensors,
              stationName == null ? 'Add a remote station' : 'Remote station: $stationName',
              onRemote, const BorderRadius.horizontal(right: Radius.circular(18))),
        ],
      ),
    );
  }
}

/// Record a new session, or stop the one recording: a madder dot when idle,
/// a stop square with a slow pulse around it while recording, a spinner
/// while it starts.
class RecordButton extends StatefulWidget {
  const RecordButton({super.key, required this.recording, required this.busy, required this.onTap});

  final bool recording;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.recording) _pulse.repeat();
  }

  @override
  void didUpdateWidget(RecordButton old) {
    super.didUpdateWidget(old);
    if (widget.recording && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.recording && _pulse.isAnimating) _pulse.reset();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    const size = 36.0;
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.recording)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Container(
                width: size * 0.7 + 14 * _pulse.value,
                height: size * 0.7 + 14 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: red.withValues(alpha: 0.25 * (1 - _pulse.value)),
                ),
              ),
            ),
          widget.busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: red),
                )
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: widget.recording ? 'Stop recording' : 'Record a new session',
                  icon: Icon(widget.recording ? Icons.stop_rounded : Icons.fiber_manual_record,
                      size: widget.recording ? 24 : 18),
                  color: red,
                  onPressed: widget.onTap,
                ),
        ],
      ),
    );
  }
}
