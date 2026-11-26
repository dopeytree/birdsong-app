import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../main.dart' show paper, rule;

/// Light tactile selection haptic on iOS (safe no-op on macOS/tests).
void hapticTap() {
  if (Platform.isIOS) {
    HapticFeedback.selectionClick();
  }
}

/// Unified translucent frosted-paper surface shared across floating controls
/// (Filters bar, Share & Stations popovers, Map Layers, Search results, Map
/// tooltips, pin cards, and bottom detection tickets) so floating depth and
/// visual polish stay 100% consistent everywhere.
class PaperSurface extends StatelessWidget {
  const PaperSurface({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.margin,
    this.opacity = 0.88,
    this.blur = 12,
    this.showBorder = true,
    this.shadow = true,
    this.constraints,
    this.width,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double opacity;
  final double blur;
  final bool showBorder;
  final bool shadow;
  final BoxConstraints? constraints;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    Widget inner = Container(
      width: width,
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: paper.withValues(alpha: opacity),
        borderRadius: radius,
        border: showBorder ? Border.all(color: rule.withValues(alpha: 0.48)) : null,
      ),
      child: child,
    );
    if (blur > 0) {
      inner = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: inner,
        ),
      );
    }
    return Container(
      margin: margin,
      decoration: shadow
          ? BoxDecoration(
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(color: Color(0x262A241C), offset: Offset(0, 4), blurRadius: 16),
              ],
            )
          : null,
      child: inner,
    );
  }
}

/// Automatic GPU contrast-inverting wrapper (`BlendMode.difference`).
///
/// Children drawn in [adaptiveInkSource] (`#C4C1B2`, the exact difference
/// complement of `ink` `#2A241C` against `paper` `#EEE5CE`) composite as:
/// - exact `#2A241C` (`ink`) over the warm paper background
/// - crisp bright cream-white over dark bird illustrations or dark map areas
///
/// Works automatically pixel-by-pixel across the entire app without manual
/// luminance sampling.
const adaptiveInkSource = Color(0xFFC4C1B2);

class AdaptiveContrast extends SingleChildRenderObjectWidget {
  const AdaptiveContrast({super.key, required super.child, this.enabled = true});

  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAdaptiveContrast(enabled);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderAdaptiveContrast).enabled = enabled;
  }
}

class _RenderAdaptiveContrast extends RenderProxyBox {
  _RenderAdaptiveContrast(this._enabled);

  bool _enabled;
  set enabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (!_enabled) {
      context.paintChild(child!, offset);
      return;
    }
    final bounds = offset & size;
    context.canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.difference);
    context.paintChild(child!, offset);
    context.canvas.restore();
  }
}
