import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart'
    as face_tflite;
import 'package:flutter/material.dart';

import '../database/app_database.dart';

class FaceVerificationScreen extends StatefulWidget {
  final int userId;
  final String fullName;

  const FaceVerificationScreen({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<FaceVerificationScreen> createState() =>
      _FaceVerificationScreenState();
}

class _FaceVerificationScreenState
    extends State<FaceVerificationScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  face_tflite.FaceDetector? _detector;

  bool _initializing = true;
  bool _processing = false;
  bool _disposed = false;

  String _message = 'Đang khởi tạo camera...';

  // Ngưỡng ban đầu để thử nghiệm, cần hiệu chỉnh bằng dữ liệu thực tế.
  static const double _similarityThreshold = 0.75;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_disposed) return;

    if (mounted) {
      setState(() {
        _initializing = true;
        _message = 'Đang khởi tạo camera và mô hình...';
      });
    }

    try {
      await _releaseCamera();

      final cameras = await availableCameras();
      if (_disposed) return;

      if (cameras.isEmpty) {
        throw Exception('Không tìm thấy camera trên thiết bị.');
      }

      final frontCameras = cameras
          .where(
            (camera) =>
                camera.lensDirection == CameraLensDirection.front,
          )
          .toList();

      final selectedCamera =
          frontCameras.isNotEmpty ? frontCameras.first : cameras.first;

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _cameraController = controller;
      await controller.initialize();

      if (_disposed) {
        await controller.dispose();
        return;
      }

      _detector ??= await face_tflite.FaceDetector.create();

      if (_disposed || !mounted) return;

      setState(() {
        _initializing = false;
        _message =
            'Đặt khuôn mặt vào giữa khung hình, nhìn thẳng và đủ ánh sáng.';
      });
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() {
          _initializing = false;
          _message = 'Không thể mở camera hoặc mô hình: $e';
        });
      }
    }
  }

  Future<void> _verifyFace() async {
    if (_processing || _initializing || _disposed) return;

    final controller = _cameraController;
    final detector = _detector;

    if (controller == null ||
        !controller.value.isInitialized ||
        detector == null) {
      _showMessage('Camera chưa sẵn sàng. Vui lòng thử lại.');
      return;
    }

    setState(() {
      _processing = true;
      _message = 'Đang kiểm tra khuôn mặt...';
    });

    try {
      final savedEmbedding =
          await AppDatabase.instance.getFaceEmbedding(widget.userId);

      if (_disposed || !mounted) return;

      if (savedEmbedding == null || savedEmbedding.isEmpty) {
        throw Exception(
          'Bạn chưa đăng ký khuôn mặt. Hãy đăng ký trước khi chấm công.',
        );
      }

      if (!controller.value.isInitialized) {
        throw Exception('Camera chưa sẵn sàng.');
      }

      final photo = await controller.takePicture();
      final Uint8List imageBytes = await photo.readAsBytes();

      if (_disposed || !mounted) return;

      final faces = await detector.detectFacesFromBytes(
        imageBytes,
        mode: face_tflite.FaceDetectionMode.full,
      );

      if (_disposed || !mounted) return;

      if (faces.length != 1) {
        throw Exception(
          faces.isEmpty
              ? 'Không tìm thấy khuôn mặt. Hãy nhìn thẳng camera và thử lại.'
              : 'Phát hiện nhiều khuôn mặt. Chỉ để một người trong khung hình.',
        );
      }

      final currentEmbedding =
          await detector.getFaceEmbedding(faces.first, imageBytes);

      if (_disposed || !mounted) return;

      if (currentEmbedding.isEmpty ||
          currentEmbedding.any((value) => !value.isFinite)) {
        throw Exception('Không thể đọc dữ liệu khuôn mặt. Hãy thử lại.');
      }

      final saved = Float32List.fromList(
        savedEmbedding.map((value) => value.toDouble()).toList(),
      );

      final current = Float32List.fromList(
        currentEmbedding.map((value) => value.toDouble()).toList(),
      );

      if (saved.length != current.length) {
        throw Exception(
          'Dữ liệu khuôn mặt không tương thích. Hãy đăng ký lại khuôn mặt.',
        );
      }

      final similarity = face_tflite.FaceDetector.compareFaces(
        saved,
        current,
      );

      if (!similarity.isFinite ||
          similarity < _similarityThreshold) {
        throw Exception(
          'Khuôn mặt chưa khớp với hồ sơ đã đăng ký. Vui lòng thử lại.',
        );
      }

      if (!_disposed && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!_disposed && mounted) {
        _showMessage('Xác minh thất bại: $e');
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted || _disposed) return;

    setState(() {
      _message = message;
    });
  }

  Future<void> _releaseCamera() async {
    final controller = _cameraController;
    _cameraController = null;

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_releaseCamera());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initialize());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);

    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }

    final detector = _detector;
    _detector = null;
    if (detector != null) {
      unawaited(detector.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final cameraReady = controller != null &&
        controller.value.isInitialized &&
        !_initializing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác minh khuôn mặt'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Nhân viên: ${widget.fullName}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: cameraReady
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: CameraPreview(controller),
                          ),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      cameraReady && !_processing ? _verifyFace : null,
                  icon: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.face),
                  label: Text(
                    _processing
                        ? 'Đang xác minh...'
                        : 'Xác minh khuôn mặt',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}