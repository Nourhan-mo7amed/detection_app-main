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
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();

      final uiImage = await decodeImageFromList(bytes);
      final result = await _pipeline.run(bytes);

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
        setState(() {
          _processing = false;
        });
        return;
      }

      // API call لو فيه QR
      if (result.qr != null && result.qr!.isNotEmpty) {
        await _apiClient.sendSingleProduct(
          productId: result.qr!,
          maxDefects: result.defects.length,
          finalStatus: result.status,
        );
      }

      setState(() {
        _image = uiImage;
        _result = result;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _processing = false;
      });
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
        title: const Text('Single Image QC'),
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
