import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config.dart';
import '../models/detection.dart';
import 'carton_detector.dart';
import 'defect_detector.dart';

class SingleImagePipeline {
  final CartonDetector cartonDetector;
  final DefectDetector defectDetector;

  SingleImagePipeline({
    required this.cartonDetector,
    required this.defectDetector,
  });

  /// الفانكشن الرئيسية اللى احنا بنناديها من main:
  /// - تاخد bytes للصورة (من الكاميرا)
  /// - ترجع SingleFrameResult فيه:
  ///   carton + defects + qr + status
  Future<SingleFrameResult?> run(Uint8List imageBytes) async {
    // 1) نفك ترميز الصورة
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final origW = decoded.width;
    final origH = decoded.height;

    // 2) Detect carton (YOLO box model على الصورة الكاملة)
    final cartons = await cartonDetector.detectCartons(decoded);
    print('📦 Detected Cartons Count: ${cartons.length}');
    if (cartons.isEmpty) return null;

    // ناخد أحسن بوكس (أعلى score)
    final carton = cartons.reduce((a, b) => a.score > b.score ? a : b);

    // 3) Crop للكرتونة بس (من غير expand) علشان الـ QR
    int qrX1 = carton.x1.toInt().clamp(0, origW - 1);
    int qrY1 = carton.y1.toInt().clamp(0, origH - 1);
    int qrX2 = carton.x2.toInt().clamp(0, origW - 1);
    int qrY2 = carton.y2.toInt().clamp(0, origH - 1);

    if (qrX2 <= qrX1 || qrY2 <= qrY1) {
      // cropping فاسد
      return null;
    }

    final qrCrop = img.copyCrop(
      decoded,
      x: qrX1,
      y: qrY1,
      width: qrX2 - qrX1,
      height: qrY2 - qrY1,
    );

    // 4) قراءة الـ QR من الكروب باستخدام mobile_scanner.analyzeImage
    final qrText = await _readQrWithMobileScanner(qrCrop);

    // 5) Expand حوالين الكرتونة علشان defect model (لو تحب تزود expandRatio من config)
    final bw = carton.x2 - carton.x1;
    final bh = carton.y2 - carton.y1;

    final padX = (bw * AppConfig.expandRatio).toInt();
    final padY = (bh * AppConfig.expandRatio).toInt();

    int dx1 = (carton.x1.toInt() - padX).clamp(0, origW - 1);
    int dy1 = (carton.y1.toInt() - padY).clamp(0, origH - 1);
    int dx2 = (carton.x2.toInt() + padX).clamp(0, origW - 1);
    int dy2 = (carton.y2.toInt() + padY).clamp(0, origH - 1);

    if (dx2 <= dx1 || dy2 <= dy1) {
      return null;
    }

    final defectCrop = img.copyCrop(
      decoded,
      x: dx1,
      y: dy1,
      width: dx2 - dx1,
      height: dy2 - dy1,
    );

    // 6) Detect defects على الـ expanded crop
    final defectLocal = await defectDetector.detectDefects(defectCrop);

    // 7) تحويل الكوردينات من local (جوا الكروب) لـ global (على الصورة الأصلية)
    final defectGlobal = defectLocal
        .map(
          (d) => Detection(
            x1: d.x1 + dx1,
            y1: d.y1 + dy1,
            x2: d.x2 + dx1,
            y2: d.y2 + dy1,
            score: d.score,
            cls: d.cls,
          ),
        )
        .toList();

    print('⚠️ Defects found in selected carton: ${defectGlobal.length}');

    // 8) تحديد الـ status النهائي
    final status = defectGlobal.isNotEmpty ? 'defect' : 'ok';

    // 9) نرجّع النتيجة
    return SingleFrameResult(
      carton: carton,
      defects: defectGlobal,
      qr: qrText,
      status: status,
    );
  }

  /// قراءة الـ QR من صورة img.Image باستخدام mobile_scanner.analyzeImage
  ///
  /// - بنحوّل الـ image لـ PNG bytes
  /// - نكتبها فى ملف temporary
  /// - ننادي MobileScannerController.analyzeImage(path)
  /// - نرجّع rawValue لو لاقى QR، أو null لو مفيش
  Future<String?> _readQrWithMobileScanner(img.Image image) async {
    try {
      // 1) encode الصورة لـ PNG فى الذاكرة
      final bytes = Uint8List.fromList(img.encodePng(image));

      // 2) نكتبها فى ملف مؤقت
      final tempDir = Directory.systemTemp;
      final file = await File(
        '${tempDir.path}/qr_${DateTime.now().microsecondsSinceEpoch}.png',
      ).create();
      await file.writeAsBytes(bytes);

      // 3) نعمل Controller مخصوص للصورة (مش للكاميرا)
      final controller = MobileScannerController(
        autoStart: false,
        formats: const [BarcodeFormat.qrCode],
      );

      try {
        final capture = await controller.analyzeImage(file.path);
        if (capture == null || capture.barcodes.isEmpty) {
          return null;
        }

        final raw = capture.barcodes.first.rawValue?.trim();
        if (raw == null || raw.isEmpty) return null;
        return raw;
      } finally {
        // نخلّص الـ controller ونمسح الملف المؤقت
        await controller.dispose();
        try {
          await file.delete();
        } catch (_) {
          // مش مهم لو الملف ما اتمسحش، مش هنبوظ حاجة
        }
      }
    } catch (_) {
      return null;
    }
  }
}
