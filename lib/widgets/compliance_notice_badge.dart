import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The single canonical compliance statement for the app. Anywhere this needs
/// to be surfaced, show [ComplianceNoticeBadge] rather than restating it, so
/// the wording only ever lives in one place.
const kComplianceNotice =
    'Independent sports research and intelligence only. '
    'Prop Intelligence does not facilitate wagering or accept bets.';

/// Compact compliance affordance: just the research-only badge until it is
/// selected, at which point [kComplianceNotice] reveals beneath it. Keeps the
/// statement present without a banner covering the surrounding UI.
class ComplianceNoticeBadge extends StatefulWidget {
  /// Diameter of the badge itself.
  final double size;

  /// Resting opacity of the badge; it brightens while the notice is open.
  final double opacity;

  /// Size of the revealed notice text.
  final double fontSize;

  /// Colour of the revealed notice text. Defaults to a dim neutral.
  final Color? textColor;

  /// Horizontal placement of the badge within its parent.
  final CrossAxisAlignment alignment;

  const ComplianceNoticeBadge({
    super.key,
    this.size = 26,
    this.opacity = 0.6,
    this.fontSize = 10.5,
    this.textColor,
    this.alignment = CrossAxisAlignment.center,
  });

  @override
  State<ComplianceNoticeBadge> createState() => _ComplianceNoticeBadgeState();
}

class _ComplianceNoticeBadgeState extends State<ComplianceNoticeBadge> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.textColor ?? const Color(0xFFC5C8CC).withValues(alpha: 0.42);
    final centred = widget.alignment == CrossAxisAlignment.center;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.alignment,
      children: [
        Semantics(
          button: true,
          label: 'Compliance notice',
          child: Tooltip(
            message: kComplianceNotice,
            child: InkResponse(
              onTap: () => setState(() => _open = !_open),
              customBorder: const CircleBorder(),
              radius: widget.size * 0.75,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ResearchOnlyBadge(
                  size: widget.size,
                  opacity: _open ? 0.9 : widget.opacity,
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    kComplianceNotice,
                    textAlign: centred ? TextAlign.center : TextAlign.left,
                    style: TextStyle(
                      color: textColor,
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      height: 1.35,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Research-and-tracking-only mark: gold ring, shielded check over a trend
/// line, struck through to signal that no wagering happens here. Painted
/// rather than loaded so it stays crisp at badge sizes and dims cleanly.
///
/// Design source: assets/branding/research_tracking_badge.svg
class ResearchOnlyBadge extends StatelessWidget {
  final double size;
  final double opacity;

  const ResearchOnlyBadge({super.key, this.size = 26, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _ResearchOnlyBadgePainter()),
      ),
    );
  }
}

class _ResearchOnlyBadgePainter extends CustomPainter {
  const _ResearchOnlyBadgePainter();

  static const _badgeGold = Color(0xFFE7B84F);
  static const _badgeFill = Color(0xFF101720);
  static const _badgeSlash = Color(0xFFF3CE68);

  @override
  void paint(Canvas canvas, Size size) {
    // The badge is authored on a 96x96 grid; scale that grid to fit.
    canvas.save();
    canvas.scale(size.shortestSide / 96);

    final goldShader = ui.Gradient.linear(
      const Offset(20, 14),
      const Offset(76, 82),
      const [Color(0xFFFFF0A8), _badgeGold, Color(0xFFA86D16)],
      const [0.0, 0.45, 1.0],
    );
    const center = Offset(48, 48);

    canvas.drawCircle(center, 43, Paint()..color = _badgeFill);
    canvas.drawCircle(
      center,
      43,
      Paint()
        ..shader = goldShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      center,
      35,
      Paint()
        ..color = _badgeGold.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    Paint strokePaint(double width) => Paint()
      ..shader = goldShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final trend = Path()
      ..moveTo(29, 62)
      ..lineTo(40, 50)
      ..lineTo(48, 56)
      ..lineTo(67, 35);
    canvas.drawPath(
      trend,
      strokePaint(5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(trend, strokePaint(5));

    final arrowHead = Path()
      ..moveTo(58, 35)
      ..lineTo(67, 35)
      ..lineTo(67, 44);
    canvas.drawPath(arrowHead, strokePaint(5));

    final shield = Path()
      ..moveTo(48, 21)
      ..cubicTo(40, 21, 34, 25, 34, 31)
      ..lineTo(34, 40)
      ..cubicTo(34, 49, 40, 57, 48, 61)
      ..cubicTo(56, 57, 62, 49, 62, 40)
      ..lineTo(62, 31)
      ..cubicTo(62, 25, 56, 21, 48, 21)
      ..close();
    canvas.drawPath(shield, Paint()..color = _badgeFill);
    canvas.drawPath(
      shield,
      Paint()
        ..color = _badgeGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final check = Path()
      ..moveTo(42, 35)
      ..lineTo(46, 39)
      ..lineTo(54, 31);
    canvas.drawPath(check, strokePaint(3.5));

    canvas.drawLine(
      const Offset(24, 72),
      const Offset(72, 24),
      Paint()
        ..color = _badgeSlash
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ResearchOnlyBadgePainter oldDelegate) => false;
}
