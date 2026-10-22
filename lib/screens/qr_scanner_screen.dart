import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../database/app_database.dart';

class QrScannerScreen extends StatefulWidget {
  final int expectedUserId;

  const QrScannerScreen({super.key, required this.expectedUserId});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;

  bool _processing = false;
  bool _loading = false;
  bool _verified = false;
  bool _cameraError = false;
  bool _cameraReady = false;
  bool _frontCamera = false;

  String _message = 'Đang khởi động camera...';
  String _qrContent = '';
  Map<String, Object?>? _user;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );

    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_processing &&
        !_loading &&
        !_cameraError) {
      _startCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopCamera();
    }
  }

  Future<void> _startCamera() async {
    if (!mounted || _processing || _loading) return;

    try {
      await _controller.start();

      if (!mounted) return;

      setState(() {
        _cameraReady = true;
        _cameraError = false;
        _message = 'Camera sẵn sàng. Hãy đưa mã QR vào khung hình.';
      });
    } catch (e) {
      debugPrint('Không thể khởi động camera: $e');

      if (!mounted) return;

      setState(() {
        _cameraReady = false;
        _cameraError = true;
        _message =
            'Không mở được camera. Hãy kiểm tra quyền camera '
            'và cấu hình camera của máy ảo Android.';
      });
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _controller.stop();
    } catch (e) {
      debugPrint('Lỗi dừng camera: $e');
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _loading || _verified || _cameraError) return;

    String? content;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        content = value;
        break;
      }
    }

    if (content == null) return;

    setState(() {
      _processing = true;
      _loading = true;
      _qrContent = content!;
      _user = null;
      _verified = false;
      _message = 'Đang xác minh tài khoản...';
    });

    await _stopCamera();

    if (!mounted) return;
    await _verifyEmployee(content);
  }

  Future<void> _verifyEmployee(String qrValue) async {
    try {
      final user = await AppDatabase.instance.findUserByUsername(
        qrValue.trim(),
      );

      if (!mounted) return;

      if (user == null) {
        setState(() {
          _loading = false;
          _processing = true;
          _message =
              'Không tìm thấy tài khoản. QR phải chứa đúng tên đăng nhập.';
        });
        return;
      }

      final id = int.tryParse(user['id']?.toString() ?? '');
      final role = user['role']?.toString().trim().toLowerCase();

      if (role != 'employee') {
        setState(() {
          _loading = false;
          _processing = true;
          _user = user;
          _message = 'Tài khoản này không có quyền chấm công nhân viên.';
        });
        return;
      }

      if (id != widget.expectedUserId) {
        setState(() {
          _loading = false;
          _processing = true;
          _user = user;
          _message = 'QR không thuộc nhân viên đang đăng nhập.';
        });
        return;
      }

      setState(() {
        _loading = false;
        _processing = true;
        _verified = true;
        _user = user;
        _message = 'Xác minh thành công! Đúng tài khoản nhân viên.';
      });
    } catch (e) {
      debugPrint('Lỗi xác minh QR: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _processing = true;
        _message = 'Lỗi xác minh tài khoản từ SQLite: $e';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_loading || _processing || _cameraError) return;

    try {
      await _controller.switchCamera();

      if (!mounted) return;

      setState(() {
        _frontCamera = !_frontCamera;
        _message = _frontCamera
            ? 'Đang sử dụng camera trước.'
            : 'Đang sử dụng camera sau.';
      });
    } catch (e) {
      debugPrint('Lỗi chuyển camera: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không chuyển được camera: $e')));
    }
  }

  Future<void> _scanAgain() async {
    if (!mounted) return;

    setState(() {
      _processing = false;
      _loading = false;
      _verified = false;
      _cameraError = false;
      _cameraReady = false;
      _qrContent = '';
      _user = null;
      _message = 'Đang khởi động camera...';
    });

    await _startCamera();
  }

  void _continueAttendance() {
    if (!_verified || _user == null) return;
    Navigator.pop(context, true);
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verified = _verified && _user != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác minh QR nhân viên'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Chuyển camera',
            onPressed: _processing || _loading || _cameraError
                ? null
                : _switchCamera,
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'XÁC MINH NHÂN VIÊN BẰNG QR',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _frontCamera ? 'Camera trước' : 'Camera sau',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!_cameraError)
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) {
                          return Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Camera gặp lỗi:\n${error.errorCode.name}\n'
                              'Kiểm tra quyền camera và cấu hình máy ảo.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        },
                      )
                    else
                      Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        child: const Text(
                          'Camera chưa hoạt động.\n'
                          'Nhấn nút thử lại bên dưới.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.greenAccent,
                              width: 4,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    if (_loading)
                      Container(
                        color: Colors.black45,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _processing || _loading || _cameraError
                  ? null
                  : _switchCamera,
              icon: const Icon(Icons.cameraswitch),
              label: const Text('Chuyển camera trước / sau'),
            ),
            if (_cameraError || !_cameraReady)
              FilledButton.icon(
                onPressed: _scanAgain,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử mở camera lại'),
              ),
            const SizedBox(height: 12),
            Card(
              color: _loading
                  ? Colors.blue.shade50
                  : verified
                  ? Colors.green.shade50
                  : _processing
                  ? Colors.red.shade50
                  : Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      _loading
                          ? Icons.hourglass_top
                          : verified
                          ? Icons.check_circle
                          : _processing
                          ? Icons.error
                          : Icons.qr_code_scanner,
                      size: 42,
                      color: _loading
                          ? Colors.blue
                          : verified
                          ? Colors.green
                          : _processing
                          ? Colors.red
                          : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_user != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'THÔNG TIN TÀI KHOẢN',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(height: 24),
                      _infoRow('Mã nhân viên', '${_user!['id'] ?? ''}'),
                      _infoRow('Họ và tên', '${_user!['full_name'] ?? ''}'),
                      _infoRow('Tên đăng nhập', '${_user!['username'] ?? ''}'),
                      _infoRow('Email', '${_user!['email'] ?? ''}'),
                      _infoRow('Vai trò', '${_user!['role'] ?? ''}'),
                    ],
                  ),
                ),
              ),
            ],
            if (_qrContent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nội dung QR đã đọc:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(_qrContent),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (verified)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _continueAttendance,
                  icon: const Icon(Icons.verified_user),
                  label: const Text('Xác nhận và tiếp tục chấm công'),
                ),
              ),
            if (_processing && !verified)
              OutlinedButton.icon(
                onPressed: _scanAgain,
                icon: const Icon(Icons.refresh),
                label: const Text('Quét lại mã QR'),
              ),
          ],
        ),
      ),
    );
  }
}
