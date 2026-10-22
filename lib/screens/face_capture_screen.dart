import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart'
    as face_tflite;

import '../database/app_database.dart';

class FaceCaptureScreen extends StatefulWidget {
  final int userId;
  final String fullName;

  const FaceCaptureScreen({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  face_tflite.FaceDetector? _faceDetector;

  bool _initializing = true;
  bool _cameraReady = false;
  bool _saving = false;
  bool _disposed = false;

  String _message = 'Đang khởi tạo camera và mô hình nhận diện...';

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
        _cameraReady = false;
        _message = 'Đang khởi tạo camera...';
      });
    }

    try {
      await _disposeCamera();

      final cameras = await availableCameras();

      if (_disposed) return;

      if (cameras.isEmpty) {
        throw Exception(
          'Không tìm thấy camera. Hãy kiểm tra thiết bị hoặc máy ảo.',
        );
      }

      CameraDescription selectedCamera;

      final frontCameras = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.front)
          .toList();

      if (frontCameras.isNotEmpty) {
        selectedCamera = frontCameras.first;
      } else {
        selectedCamera = cameras.first;
      }

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

      if (_faceDetector == null) {
        if (mounted) {
          setState(() {
            _message = 'Đang tải mô hình nhận diện khuôn mặt...';
          });
        }

        _faceDetector = await face_tflite.FaceDetector.create();
      }

      if (_disposed) return;

      if (mounted) {
        setState(() {
          _initializing = false;
          _cameraReady = true;
          _message =
              'Đưa khuôn mặt vào giữa khung hình, nhìn thẳng và đủ ánh sáng.';
        });
      }
    } catch (e) {
      await _disposeCamera();

      if (!_disposed && mounted) {
        setState(() {
          _initializing = false;
          _cameraReady = false;
          _message = 'Không thể khởi tạo camera hoặc mô hình: $e';
        });
      }
    }
  }

  Future<void> _registerFace() async {
    if (_saving || !_cameraReady || _disposed) return;

    final controller = _cameraController;
    final detector = _faceDetector;

    if (controller == null ||
        !controller.value.isInitialized ||
        detector == null) {
      _showMessage('Camera hoặc mô hình chưa sẵn sàng.');
      return;
    }

    setState(() {
      _saving = true;
      _message = 'Đang chụp ảnh và phân tích khuôn mặt...';
    });

    try {
      // Chụp ảnh JPEG từ camera.
      final XFile photo = await controller.takePicture();
      final Uint8List imageBytes = await photo.readAsBytes();

      if (_disposed) return;

      // Phát hiện khuôn mặt bằng face_detection_tflite.
      final faces = await detector.detectFacesFromBytes(
        imageBytes,
        mode: face_tflite.FaceDetectionMode.full,
      );

      if (_disposed || !mounted) return;

      if (faces.isEmpty) {
        _showMessage(
          'Không tìm thấy khuôn mặt. Hãy nhìn thẳng vào camera '
          'và thử lại.',
        );
        return;
      }

      if (faces.length != 1) {
        _showMessage(
          'Ảnh phải có đúng một khuôn mặt. '
          'Hãy đảm bảo không có người khác trong khung hình.',
        );
        return;
      }

      final face = faces.first;

      // Mô hình embedding cần các điểm mốc mắt.
      final leftEye = face.landmarks.leftEye;
      final rightEye = face.landmarks.rightEye;

      if (leftEye == null || rightEye == null) {
        _showMessage(
          'Không xác định được hai mắt. Hãy tăng ánh sáng, '
          'bỏ vật che mặt và chụp lại.',
        );
        return;
      }

      if (mounted) {
        setState(() {
          _message = 'Đang tạo mã đặc trưng khuôn mặt...';
        });
      }

      // Tạo embedding từ ảnh và khuôn mặt vừa phát hiện.
      final embedding = await detector.getFaceEmbedding(face, imageBytes);

      if (_disposed || !mounted) return;

      if (embedding.isEmpty || embedding.any((value) => !value.isFinite)) {
        _showMessage(
          'Mô hình trả về dữ liệu khuôn mặt không hợp lệ. '
          'Vui lòng chụp lại.',
        );
        return;
      }

      // Lưu embedding thật vào bảng face_profiles của SQLite.
      await AppDatabase.instance.saveFaceProfile(
        userId: widget.userId,
        faceEmbedding: embedding.toList(),
      );

      if (_disposed || !mounted) return;

      setState(() {
        _message = 'Đăng ký khuôn mặt thành công!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã tạo và lưu mã đặc trưng khuôn mặt vào SQLite.'),
          backgroundColor: Colors.green,
        ),
      );

      // Trả kết quả thành công cho màn hình gọi chức năng này.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!_disposed && mounted) {
        _showMessage('Không thể đăng ký khuôn mặt: $e');
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _saving = false;
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

  Future<void> _disposeCamera() async {
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
      unawaited(_disposeCamera());
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

    final detector = _faceDetector;
    _faceDetector = null;

    if (detector != null) {
      unawaited(detector.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký khuôn mặt')),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.teal.withValues(alpha: 0.08),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_circle,
                    size: 44,
                    color: Colors.teal,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.fullName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Mã nhân viên: ${widget.userId}'),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _initializing
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Đang chuẩn bị camera và mô hình...'),
                        ],
                      )
                    : _cameraReady && _cameraController != null
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CameraPreview(_cameraController!),
                          ),
                          Container(
                            width: 240,
                            height: 300,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.tealAccent,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(140),
                            ),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.no_photography,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 12),
                            Text(_message, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _initialize,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    _cameraReady
                        ? Icons.face_retouching_natural
                        : Icons.info_outline,
                    color: _cameraReady ? Colors.teal : Colors.blueGrey,
                    size: 34,
                  ),
                  const SizedBox(height: 10),
                  Text(_message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _cameraReady && !_saving
                          ? _registerFace
                          : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt),
                      label: Text(
                        _saving ? 'Đang xử lý...' : 'Chụp và đăng ký khuôn mặt',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ảnh chỉ được dùng để tạo mã đặc trưng '
                    'và không được lưu thành hồ sơ ảnh trong đoạn code này.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
