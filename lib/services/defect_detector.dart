import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

import '../config.dart';
import '../models/detection.dart';

class DefectDetector {
  tfl.Interpreter? _interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;

  bool get isLoaded => _interpreter != null;

  Future<void> loadModel() async {
    _interpreter ??= await tfl.Interpreter.fromAsset(
      'assets/models/defect_model.tflite',
    );
    final input = _interpreter!.getInputTensor(0);
    final output = _interpreter!.getOutputTensor(0);
    _inputShape = input.shape;
    _outputShape = output.shape;
  }

  Future<List<Detection>> detectDefects(img.Image crop) async {
    if (!isLoaded) {
      await loadModel();
    }
    final interpreter = _interpreter!;
    final inputShape = _inputShape!;
    final outputShape = _outputShape!;

    final modelH = inputShape[1];
    final modelW = inputShape[2];

    final cropW = crop.width;
    final cropH = crop.height;

    final resized = img.copyResize(crop, width: modelW, height: modelH);

    final input = List.generate(
      1,
      (_) => List.generate(
        modelH,
        (y) => List.generate(modelW, (x) {
          final pixel = resized.getPixel(x, y);
          final r = pixel.r / 255.0;
          final g = pixel.g / 255.0;
          final b = pixel.b / 255.0;
          return [r, g, b];
        }),
      ),
    );

    final out0 = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List.filled(outputShape[2], 0.0),
      ),
    );

    interpreter.run(input, out0);

    return _parseDefects(
      out0,
      cropW: cropW,
      cropH: cropH,
      modelW: modelW,
      modelH: modelH,
    );
  }

  List<Detection> _parseDefects(
    List<dynamic> rawOutput, {
    required int cropW,
    required int cropH,
    required int modelW,
    required int modelH,
  }) {
    const double confThreshold = AppConfig.defectConf;
    final List<Detection> detections = [];

    final out0 = rawOutput[0] as List<dynamic>; // [5][8400]
    final cxList = (out0[0] as List).cast<double>();
    final cyList = (out0[1] as List).cast<double>();
    final wList = (out0[2] as List).cast<double>();
    final hList = (out0[3] as List).cast<double>();
    final confList = (out0[4] as List).cast<double>();

    final int numBoxes = cxList.length;

    final scaleX = cropW / modelW;
    final scaleY = cropH / modelH;

    for (int i = 0; i < numBoxes; i++) {
      final conf = confList[i];
      if (conf < confThreshold) continue;

      final cx = cxList[i];
      final cy = cyList[i];
      final w = wList[i];
      final h = hList[i];

      final mx1 = (cx - w / 2.0) * modelW;
      final my1 = (cy - h / 2.0) * modelH;
      final mx2 = (cx + w / 2.0) * modelW;
      final my2 = (cy + h / 2.0) * modelH;

      double x1 = mx1 * scaleX;
      double y1 = my1 * scaleY;
      double x2 = mx2 * scaleX;
      double y2 = my2 * scaleY;

      x1 = x1.clamp(0, cropW.toDouble());
      y1 = y1.clamp(0, cropH.toDouble());
      x2 = x2.clamp(0, cropW.toDouble());
      y2 = y2.clamp(0, cropH.toDouble());

      if (x2 <= x1 || y2 <= y1) continue;

      detections.add(
        Detection(x1: x1, y1: y1, x2: x2, y2: y2, score: conf, cls: 0),
      );
    }

    // Apply NMS
    return _nms(detections, 0.45);
  }

  List<Detection> _nms(List<Detection> detections, double iouThreshold) {
    if (detections.isEmpty) return [];

    // Sort by score descending
    detections.sort((a, b) => b.score.compareTo(a.score));

    final List<Detection> result = [];
    final List<bool> suppressed = List.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      final current = detections[i];
      result.add(current);

      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;

        final other = detections[j];
        if (_iou(current, other) > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return result;
  }

  double _iou(Detection a, Detection b) {
    final x1 = a.x1 > b.x1 ? a.x1 : b.x1;
    final y1 = a.y1 > b.y1 ? a.y1 : b.y1;
    final x2 = a.x2 < b.x2 ? a.x2 : b.x2;
    final y2 = a.y2 < b.y2 ? a.y2 : b.y2;

    if (x2 <= x1 || y2 <= y1) return 0.0;

    final intersection = (x2 - x1) * (y2 - y1);
    final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);

    return intersection / (areaA + areaB - intersection);
  }
}
