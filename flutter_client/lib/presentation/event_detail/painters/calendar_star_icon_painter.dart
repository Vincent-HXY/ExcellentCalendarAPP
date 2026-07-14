import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';

class CalendarStarIconPainter extends CustomPainter {
  const CalendarStarIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = EventDetailColors.primaryTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = EventDetailColors.primaryTeal
      ..style = PaintingStyle.fill;
    final calendar = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .1,
        size.height * .18,
        size.width * .8,
        size.height * .7,
      ),
      Radius.circular(size.width * .12),
    );
    canvas.drawRRect(calendar, stroke);
    canvas.drawLine(
      Offset(size.width * .1, size.height * .39),
      Offset(size.width * .9, size.height * .39),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .3, size.height * .08),
      Offset(size.width * .3, size.height * .28),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .7, size.height * .08),
      Offset(size.width * .7, size.height * .28),
      stroke,
    );

    final center = Offset(size.width * .62, size.height * .63);
    final star = Path();
    for (var index = 0; index < 10; index++) {
      final radius = index.isEven ? size.width * .17 : size.width * .075;
      final angle = -math.pi / 2 + index * math.pi / 5;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (index == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();
    canvas.drawPath(star, fill);
  }

  @override
  bool shouldRepaint(covariant CalendarStarIconPainter oldDelegate) => false;
}
