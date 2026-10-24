import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A tiled diagonal watermark overlay widget designed to deter physical camera
/// leaks of sensitive screens.
///
/// Wrap any sensitive page or widget with [ScreenProtectionWatermark] to render
/// a non-interactive (`IgnorePointer`) tiled watermark across its bounds.
class ScreenProtectionWatermark extends StatelessWidget {
  /// Creates a [ScreenProtectionWatermark].
  const ScreenProtectionWatermark({
    super.key,
    required this.child,
    required this.text,
    this.subText,
    this.enabled = true,
    this.angleDegrees = -24.0,
    this.horizontalSpacing = 180.0,
    this.verticalSpacing = 120.0,
    this.textStyle,
    this.opacity = 0.12,
  }) : assert(horizontalSpacing > 20.0, 'horizontalSpacing must be > 20.0'),
       assert(verticalSpacing > 20.0, 'verticalSpacing must be > 20.0'),
       assert(opacity >= 0.0 && opacity <= 1.0, 'opacity must be in 0..1');

  /// The child widget protected by the watermark overlay.
  final Widget child;

  /// Primary watermark text (e.g. username, employee ID, or session token).
  final String text;

  /// Optional secondary line (e.g. timestamp, IP address, or department).
  final String? subText;

  /// Whether the watermark overlay is visible.
  final bool enabled;

  /// Rotation angle in degrees for each watermark tile (defaults to `-24.0`).
  final double angleDegrees;

  /// Horizontal distance between adjacent watermark tiles in logical pixels.
  final double horizontalSpacing;

  /// Vertical distance between watermark rows in logical pixels.
  final double verticalSpacing;

  /// Custom [TextStyle] for the watermark text.
  final TextStyle? textStyle;

  /// Opacity applied to the watermark layer (`0.0` to `1.0`).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (!enabled || text.trim().isEmpty) {
      return child;
    }

    final defaultColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final effectiveStyle =
        (textStyle ??
                TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: defaultColor,
                  letterSpacing: 0.6,
                ))
            .copyWith(
              color: (textStyle?.color ?? defaultColor).withValues(
                alpha: opacity,
              ),
            );

    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WatermarkPainter(
                  text: text,
                  subText: subText,
                  angleRadians: angleDegrees * math.pi / 180.0,
                  horizontalSpacing: horizontalSpacing,
                  verticalSpacing: verticalSpacing,
                  textStyle: effectiveStyle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter({
    required this.text,
    required this.subText,
    required this.angleRadians,
    required this.horizontalSpacing,
    required this.verticalSpacing,
    required this.textStyle,
  });

  final String text;
  final String? subText;
  final double angleRadians;
  final double horizontalSpacing;
  final double verticalSpacing;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final fullLabel = (subText != null && subText!.trim().isNotEmpty)
        ? '$text\n$subText'
        : text;

    final painter = TextPainter(
      text: TextSpan(text: fullLabel, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final stepX = math.max(horizontalSpacing, painter.width + 48.0);
    final stepY = math.max(verticalSpacing, painter.height + 40.0);

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final center = Offset(size.width / 2.0, size.height / 2.0);

    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleRadians);

    final halfSpan = diagonal / 2.0 + stepX;
    int rowIndex = 0;
    for (double y = -halfSpan; y <= halfSpan; y += stepY) {
      final rowOffset = (rowIndex.isOdd) ? stepX / 2.0 : 0.0;
      for (double x = -halfSpan + rowOffset; x <= halfSpan; x += stepX) {
        painter.paint(
          canvas,
          Offset(x - painter.width / 2.0, y - painter.height / 2.0),
        );
      }
      rowIndex++;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.subText != subText ||
        oldDelegate.angleRadians != angleRadians ||
        oldDelegate.horizontalSpacing != horizontalSpacing ||
        oldDelegate.verticalSpacing != verticalSpacing ||
        oldDelegate.textStyle != textStyle;
  }
}
