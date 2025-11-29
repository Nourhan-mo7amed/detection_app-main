import 'package:flutter/material.dart';
import '../models/detection.dart';

class AnnotationPainter extends CustomPainter {
  final SingleFrameResult result;
  final double imageWidth;
  final double imageHeight;

  AnnotationPainter({
    required this.result,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    // لون البوكس حسب الحالة
    final bool hasDefect = result.hasDefect;
    final cartonColor = hasDefect ? Colors.redAccent : Colors.greenAccent;

    final cartonPaint = Paint()
      ..color = cartonColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final defectPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    // carton box
    final c = result.carton;
    final rect = Rect.fromLTRB(
      c.x1 * scaleX,
      c.y1 * scaleY,
      c.x2 * scaleX,
      c.y2 * scaleY,
    );
    canvas.drawRect(rect, cartonPaint);

    // defects highlights (دويرة صغيرة في نص كل defect)
    for (final d in result.defects) {
      final cx = ((d.x1 + d.x2) / 2) * scaleX;
      final cy = ((d.y1 + d.y2) / 2) * scaleY;
      canvas.drawCircle(Offset(cx, cy), 6.0, defectPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}
