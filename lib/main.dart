import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'models/detection.dart';
import 'painters/annotation_painter.dart';
import 'services/api_client.dart';
import 'services/carton_detector.dart';
import 'services/defect_detector.dart';
import 'services/single_image_pipeline.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Single Image QC',
      theme: ThemeData.dark(),
      home: CameraPage(cameras: cameras),
    );
  }
}

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraPage({super.key, required this.cameras});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  bool _loading = true;
  bool _processing = false;

  ui.Image? _image;
  SingleFrameResult? _result;

  late final SingleImagePipeline _pipeline;
  late final ApiClient _apiClient;

  @override
  void initState() {
    super.initState();
    _pipeline = SingleImagePipeline(
      cartonDetector: CartonDetector(),
      defectDetector: DefectDetector(),
    );
    _apiClient = ApiClient();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _controller = controller;
    await controller.initialize();

    setState(() => _loading = false);
  }

  Future<void> _capture() async {
    if (_processing) return;
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _processing = true;
    });

    try {
      // 1) تصوير الصورة من الكاميرا
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();

      // 2) تحويلها لصورة UI عشان نعرضها ونرسم عليها
      final uiImage = await decodeImageFromList(bytes);

      // 3) تشغيل البايبلاين (carton + crop + defect + QR + status)
      final result = await _pipeline.run(bytes);

      // 4) لو مفيش كرتونة detected خالص
      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No carton detected! Try getting closer or adjusting angle.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        if (mounted) {
          setState(() {
            _processing = false;
          });
        } else {
          _processing = false;
        }
        return;
      }

      // 5) لو فيه QR → نبعت للـ API
      if (result.qr != null && result.qr!.isNotEmpty) {
        await _apiClient.sendSingleProduct(
          productId: result.qr!,
          maxDefects: result.defects.length,
          finalStatus: result.status,
        );
      } else {
        // مفيش QR → نعمل annotation بس، ومنبعتش للـ API
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No QR code found. Result will NOT be sent to server.',
              ),
              backgroundColor: Colors.blueGrey,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // 6) حفظ الصورة والنتيجة عشان نعرضها بالرسم
      if (!mounted) return;
      setState(() {
        _image = uiImage;
        _result = result;
      });
    } catch (e) {
      // أي خطأ في التصوير / البايبلاين / API
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing or processing image: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // 7) نرجّع حالة الـ processing لطبيعتها
      if (mounted) {
        setState(() {
          _processing = false;
        });
      } else {
        _processing = false;
      }
    }
  }

  void _reset() {
    setState(() {
      _image = null;
      _result = null;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final controller = _controller!;
    final showResult = _image != null && _result != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('حسبي الله'),
        actions: [
          if (showResult)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _reset),
        ],
      ),
      body: Center(
        child: showResult
            ? AspectRatio(
                // استخدم أبعاد الصورة نفسها عشان ما تتقصش
                aspectRatio: _image!.width / _image!.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RawImage(
                      image: _image,
                      fit: BoxFit.contain, // مهم: contain مش cover
                    ),
                    CustomPaint(
                      painter: AnnotationPainter(
                        result: _result!,
                        imageWidth: _image!.width.toDouble(),
                        imageHeight: _image!.height.toDouble(),
                      ),
                    ),
                  ],
                ),
              )
            : AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),
                    if (_processing)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
      ),
      floatingActionButton: showResult
          ? null
          : FloatingActionButton(
              onPressed: _processing ? null : _capture,
              child: const Icon(Icons.camera_alt),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
