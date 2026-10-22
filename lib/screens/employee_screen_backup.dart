
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../database/app_database.dart';
import 'attendance_map_screen.dart';
import 'face_capture_screen.dart';
import 'qr_scanner_screen.dart';

class EmployeeScreen extends StatefulWidget {
  final int userId;
  final String fullName;

  const EmployeeScreen({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  bool _loading = true;
  bool _processing = false;
  bool _hasFaceProfile = false;

  Map<String, Object?>? _todayAttendance;
  List<Map<String, Object?>> _history = [];

  String _displayName = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _displayName = widget.fullName;
    _loadAllData();
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');

    return '${now.year}-$month-$day';
  }

  Future<void> _loadAllData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final db = await AppDatabase.instance.database;
      final today = _todayKey();

      final userRows = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [widget.userId],
        limit: 1,
      );

      final todayRows = await db.query(
        'attendance',
        where: 'user_id = ? AND work_date = ?',
        whereArgs: [widget.userId, today],
        limit: 1,
      );

      final historyRows = await db.query(
        'attendance',
        where: 'user_id = ?',
        whereArgs: [widget.userId],
        orderBy: 'work_date DESC, id DESC',
      );

      final hasFace = await AppDatabase.instance.hasFaceProfile(
        widget.userId,
      );

      if (!mounted) return;

      setState(() {
        if (userRows.isNotEmpty) {
          _displayName =
              (userRows.first['full_name'] as String?) ?? widget.fullName;
        }

        _todayAttendance =
            todayRows.isNotEmpty ? todayRows.first : null;
        _history = historyRows;
        _hasFaceProfile = hasFace;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = 'Không tải được dữ liệu: $e';
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _formatTime(Object? value) {
    if (value == null) return '--:--';

    try {
      final date = DateTime.parse(value.toString()).toLocal();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$hour:$minute';
    } catch (_) {
      return value.toString();
    }
  }

  String _formatDate(Object? value) {
    if (value == null) return '--/--/----';

    try {
      final date = DateTime.parse(value.toString());
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');

      return '$day/$month/${date.year}';
    } catch (_) {
      return value.toString();
    }
  }

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Dịch vụ vị trí đang tắt. Hãy bật GPS trên thiết bị.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Bạn chưa cấp quyền truy cập vị trí.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Quyền vị trí bị từ chối vĩnh viễn. '
        'Hãy mở Cài đặt ứng dụng để cấp quyền.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
  }

  Future<void> _checkIn() async {
    if (_processing) return;

    final existingCheckIn = _todayAttendance?['check_in'];

    if (existingCheckIn != null) {
      _showMessage('Bạn đã chấm công vào hôm nay.');
      return;
    }

    setState(() => _processing = true);

    try {
      _showMessage('Đang lấy vị trí GPS...');

      final position = await _getCurrentPosition();
      final db = await AppDatabase.instance.database;
      final now = DateTime.now().toIso8601String();
      final today = _todayKey();

      final existingRows = await db.query(
        'attendance',
        columns: ['id'],
        where: 'user_id = ? AND work_date = ?',
        whereArgs: [widget.userId, today],
        limit: 1,
      );

      if (existingRows.isNotEmpty) {
        await db.update(
          'attendance',
          {
            'check_in': now,
            'check_in_latitude': position.latitude,
            'check_in_longitude': position.longitude,
          },
          where: 'id = ?',
          whereArgs: [existingRows.first['id']],
        );
      } else {
        await db.insert('attendance', {
          'user_id': widget.userId,
          'check_in': now,
          'check_out': null,
          'work_date': today,
          'check_in_latitude': position.latitude,
          'check_in_longitude': position.longitude,
          'check_out_latitude': null,
          'check_out_longitude': null,
        });
      }

      await _loadAllData();

      if (!mounted) return;

      _showMessage('Chấm công vào thành công.');
    } catch (e) {
      _showMessage('Không thể chấm công vào: $e');
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _checkOut() async {
    if (_processing) return;

    final checkIn = _todayAttendance?['check_in'];
    final checkOut = _todayAttendance?['check_out'];

    if (checkIn == null) {
      _showMessage('Bạn cần chấm công vào trước.');
      return;
    }

    if (checkOut != null) {
      _showMessage('Bạn đã chấm công ra hôm nay.');
      return;
    }

    setState(() => _processing = true);

    try {
      _showMessage('Đang lấy vị trí GPS...');

      final position = await _getCurrentPosition();
      final db = await AppDatabase.instance.database;

      await db.update(
        'attendance',
        {
          'check_out': DateTime.now().toIso8601String(),
          'check_out_latitude': position.latitude,
          'check_out_longitude': position.longitude,
        },
        where: 'user_id = ? AND work_date = ? AND check_in IS NOT NULL',
        whereArgs: [widget.userId, _todayKey()],
      );

      await _loadAllData();

      if (!mounted) return;

      _showMessage('Chấm công ra thành công.');
    } catch (e) {
      _showMessage('Không thể chấm công ra: $e');
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _openFaceCapture() async {
    if (_processing) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => FaceCaptureScreen(
          userId: widget.userId,
          fullName: _displayName,
        ),
      ),
    );

    if (!mounted) return;

    await _loadAllData();

    if (result == true && mounted) {
      _showMessage(
        'Đã hoàn tất màn hình chụp ảnh. '
        'Hãy lưu ý hồ sơ nhận diện chưa được tạo tự động.',
      );
    }
  }

  Future<void> _openQrScanner() async {
    if (_processing) return;

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute<dynamic>(
        builder: (context) => QrScannerScreen(
          expectedUserId: widget.userId,
        ),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      _showMessage('Đã quay lại từ màn hình quét QR.');
    }

    await _loadAllData();
  }

  Future<void> _openAttendanceMap() async {
    if (_processing) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AttendanceMapScreen(),
      ),
    );

    if (!mounted) return;

    await _loadAllData();
  }

  Future<void> _deleteFaceProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa hồ sơ khuôn mặt?'),
        content: const Text(
          'Thao tác này chỉ xóa hồ sơ khuôn mặt của tài khoản. '
          'Tài khoản và lịch sử chấm công vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa hồ sơ'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await AppDatabase.instance.deleteFaceProfile(widget.userId);
      await _loadAllData();

      if (!mounted) return;

      _showMessage('Đã xóa hồ sơ khuôn mặt.');
    } catch (e) {
      _showMessage('Không xóa được hồ sơ: $e');
    }
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF087F8C), Color(0xFF12A6A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.badge_outlined,
            size: 38,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          const Text(
            'SMART ATTENDANCE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Xin chào, $_displayName',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mã nhân viên: ${widget.userId}',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            'Ngày ${_formatDate(_todayKey())}',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayCard() {
    final checkIn = _todayAttendance?['check_in'];
    final checkOut = _todayAttendance?['check_out'];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE4E7EC)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chấm công hôm nay',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _timeInfo(
                    icon: Icons.login,
                    title: 'Giờ vào',
                    time: _formatTime(checkIn),
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeInfo(
                    icon: Icons.logout,
                    title: 'Giờ ra',
                    time: _formatTime(checkOut),
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed:
                    _processing || checkIn != null ? null : _checkIn,
                icon: const Icon(Icons.login),
                label: Text(
                  _processing
                      ? 'Đang xử lý...'
                      : checkIn != null
                          ? 'Đã chấm công vào'
                          : 'Chấm công vào',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _processing ||
                        checkIn == null ||
                        checkOut != null
                    ? null
                    : _checkOut,
                icon: const Icon(Icons.logout),
                label: Text(
                  checkOut != null
                      ? 'Đã chấm công ra'
                      : 'Chấm công ra',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeInfo({
    required IconData icon,
    required String title,
    required String time,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 4),
          Text(
            time,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E7EC)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildFaceCard() {
    return _buildActionCard(
      icon: Icons.face_retouching_natural,
      title: 'Đăng ký khuôn mặt',
      subtitle: _hasFaceProfile
          ? 'Tài khoản đang có hồ sơ khuôn mặt trong database'
          : 'Mở camera để chụp ảnh khuôn mặt',
      color: Colors.teal,
      onTap: _openFaceCapture,
      trailing: _hasFaceProfile
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.chevron_right),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text('Chưa có lịch sử chấm công.'),
          ),
        ),
      );
    }

    return Column(
      children: _history.map((record) {
        final checkIn = record['check_in'];
        final checkOut = record['check_out'];

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE4E7EC)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatDate(record['work_date']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      checkOut == null ? 'Chưa chấm ra' : 'Hoàn tất',
                      style: TextStyle(
                        color: checkOut == null
                            ? Colors.orange
                            : Colors.green,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Vào: ${_formatTime(checkIn)}',
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Ra: ${_formatTime(checkOut)}',
                      ),
                    ),
                  ],
                ),
                if (record['check_in_latitude'] != null &&
                    record['check_in_longitude'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'GPS vào: '
                    '${record['check_in_latitude']}, '
                    '${record['check_in_longitude']}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                    ),
                  ),
                ],
                if (record['check_out_latitude'] != null &&
                    record['check_out_longitude'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'GPS ra: '
                    '${record['check_out_latitude']}, '
                    '${record['check_out_longitude']}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Màn hình nhân viên'),
        actions: [
          IconButton(
            tooltip: 'Tải lại dữ liệu',
            onPressed: _loading ? null : _loadAllData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildTodayCard(),
                  const SizedBox(height: 20),
                  const Text(
                    'Chức năng nhân viên',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildActionCard(
                    icon: Icons.qr_code_scanner,
                    title: 'Quét mã QR',
                    subtitle: 'Mở camera quét mã chấm công',
                    color: Colors.blue,
                    onTap: _openQrScanner,
                  ),
                  _buildActionCard(
                    icon: Icons.map_outlined,
                    title: 'Bản đồ chấm công',
                    subtitle: 'Xem vị trí chấm công',
                    color: Colors.deepPurple,
                    onTap: _openAttendanceMap,
                  ),
                  _buildFaceCard(),
                  if (_hasFaceProfile)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _deleteFaceProfile,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Xóa hồ sơ khuôn mặt'),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Lịch sử chấm công',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildHistory(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
