import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr_code_vision/qr_code_vision.dart';

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

  Future<SingleFrameResult?> run(Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final origW = decoded.width;
    final origH = decoded.height;

    // 1) carton detection
    final cartons = await cartonDetector.detectCartons(decoded);
    if (cartons.isEmpty) return null;

    // ناخد أعلى ثقة
    final carton = cartons.reduce((a, b) => a.score > b.score ? a : b);

    // 2) expand + crop
    final bw = carton.x2 - carton.x1;
    final bh = carton.y2 - carton.y1;

    final padX = (bw * AppConfig.expandRatio).toInt();
    final padY = (bh * AppConfig.expandRatio).toInt();

    int x1 = (carton.x1.toInt() - padX).clamp(0, origW - 1);
    int y1 = (carton.y1.toInt() - padY).clamp(0, origH - 1);
    int x2 = (carton.x2.toInt() + padX).clamp(0, origW - 1);
    int y2 = (carton.y2.toInt() + padY).clamp(0, origH - 1);

    final crop = img.copyCrop(
      decoded,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
    );

    // 3) defect detection on crop
    final defectLocal = await defectDetector.detectDefects(crop);

    final defectGlobal = defectLocal
        .map(
          (d) => Detection(
            x1: d.x1 + x1,
            y1: d.y1 + y1,
            x2: d.x2 + x1,
            y2: d.y2 + y1,
            score: d.score,
            cls: d.cls,
          ),
        )
        .toList();

    // 4) QR from crop
    final qrText = await _readQrFromCrop(crop);

    // 5) status
    final status = defectGlobal.isNotEmpty ? 'defect' : 'ok';

    return SingleFrameResult(
      carton: carton,
      defects: defectGlobal,
      qr: qrText,
      status: status,
    );
  }

  Future<String?> _readQrFromCrop(img.Image crop) async {
    try {
      final rgba = Uint8List.fromList(
        img.copyRotate(crop, angle: 0).getBytes(order: img.ChannelOrder.rgba),
      );

      final qr = QrCode();
      qr.scanRgbaBytes(rgba, crop.width, crop.height);

      final text = qr.content?.text.trim();
      if (text == null || text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }
}
