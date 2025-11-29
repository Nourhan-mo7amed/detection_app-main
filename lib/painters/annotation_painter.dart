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

    final bool hasDefect = result.hasDefect;
    final bool hasQr = result.qr != null && result.qr!.isNotEmpty;

    // لون البوكس: أخضر لو مفيش عيوب، أحمر لو فيه عيوب
    final cartonColor =
        hasDefect ? Colors.redAccent : Colors.greenAccent;

    final cartonPaint = Paint()
      ..color = cartonColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // هايلايت العيوب: أحمر شفاف شوية
    final defectPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    // ===== رسم بوكس الكرتونة =====
    final c = result.carton;
    final left = c.x1 * scaleX;
    final top = c.y1 * scaleY;
    final right = c.x2 * scaleX;
    final bottom = c.y2 * scaleY;

    final rect = Rect.fromLTRB(left, top, right, bottom);
    canvas.drawRect(rect, cartonPaint);

    // ===== Label فوق البوكس =====
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    String label;
    if (hasQr) {
      // مثال: "B3 is DEFECT" أو "B3 is OK"
      final statusWord = hasDefect ? 'is DEFECT' : 'is OK';
      label = '${result.qr} $statusWord';
    } else {
      // مفيش QR
      label = 'NO QR CODE';
    }

    const double padding = 4.0;

    textPainter.text = TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
      ),
    );
    textPainter.layout();

    final double labelWidth = textPainter.width + padding * 2;
    final double labelHeight = textPainter.height + padding * 2;

    // نحاول نخلي الليبل فوق البوكس بشوية، ولو طلع برا الصورة ننزّله شوية
    double bgLeft = left;
    double bgTop = top - labelHeight - 4;
    if (bgTop < 0) {
      bgTop = top + 4;
    }

    final bgRect = Rect.fromLTWH(
      bgLeft,
      bgTop,
      labelWidth,
      labelHeight,
    );

    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4.0)),
      bgPaint,
    );

    textPainter.paint(
      canvas,
      Offset(bgRect.left + padding, bgRect.top + padding),
    );

    // ===== رسم الـ defect highlights =====
    for (final d in result.defects) {
      final dx1 = d.x1 * scaleX;
      final dy1 = d.y1 * scaleY;
      final dx2 = d.x2 * scaleX;
      final dy2 = d.y2 * scaleY;

      final width = (dx2 - dx1).abs();
      final height = (dy2 - dy1).abs();

      // مركز العيب
      final cx = (dx1 + dx2) / 2;
      final cy = (dy1 + dy2) / 2;

      // radius أكبر شوية من حجم العيب نفسه
      final baseRadius = (width < height ? width : height) * 0.6;
      final radius = baseRadius.clamp(8.0, 24.0);

      canvas.drawCircle(Offset(cx, cy), radius, defectPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) {
    return oldDelegate.result != result ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
