class Detection {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double score;
  final int cls;

  const Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.cls,
  });
}

class SingleFrameResult {
  final Detection carton;
  final List<Detection> defects;
  final String? qr;
  final String status; // "ok" أو "defect"

  const SingleFrameResult({
    required this.carton,
    required this.defects,
    required this.qr,
    required this.status,
  });

  bool get hasDefect => defects.isNotEmpty;
}