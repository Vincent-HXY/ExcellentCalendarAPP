import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';

class ParticipantIconPainter extends CustomPainter {
  const ParticipantIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final primary = Paint()
      ..color = EventDetailColors.primaryTeal
      ..style = PaintingStyle.fill;
    final muted = Paint()
      ..color = EventDetailColors.disabledBlueGray
      ..style = PaintingStyle.fill;

    _drawPerson(
      canvas,
      center: Offset(size.width * .31, size.height * .36),
      paint: primary,
      scale: .78,
    );
    _drawPerson(
      canvas,
      center: Offset(size.width * .52, size.height * .3),
      paint: primary,
      scale: 1,
    );
    _drawPerson(
      canvas,
      center: Offset(size.width * .73, size.height * .42),
      paint: muted,
      scale: .7,
    );
  }

  void _drawPerson(
    Canvas canvas, {
    required Offset center,
    required Paint paint,
    required double scale,
  }) {
    final headRadius = 4.2 * scale;
    canvas.drawCircle(center, headRadius, paint);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 8.1 * scale),
        width: 11.5 * scale,
        height: 7.5 * scale,
      ),
      Radius.circular(4 * scale),
    );
    canvas.drawRRect(body, paint);
  }

  @override
  bool shouldRepaint(covariant ParticipantIconPainter oldDelegate) => false;
}
