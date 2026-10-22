import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';

class AdminAttendanceReportScreen extends StatefulWidget {
  const AdminAttendanceReportScreen({super.key});

  @override
  State<AdminAttendanceReportScreen> createState() =>
      _AdminAttendanceReportScreenState();
}

class _AdminAttendanceReportScreenState
    extends State<AdminAttendanceReportScreen> {
  DateTime _selectedDate = DateTime.now();

  List<Map<String, Object?>> _records = [];
  bool _isLoading = true;
  bool _isExporting = false;

  String _searchText = '';
  String _selectedStatus = 'Tất cả';

  String get _dateString {
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  // Tải báo cáo chấm công từ SQLite.
  Future<void> _loadReport() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final db = await AppDatabase.instance.database;

      final result = await db.rawQuery(
        '''
        SELECT
          u.id AS user_id,
          u.full_name AS full_name,
          u.username AS username,
          a.id AS attendance_id,
          a.work_date AS work_date,
          a.check_in AS check_in,
          a.check_out AS check_out,
          a.check_in_latitude AS check_in_latitude,
          a.check_in_longitude AS check_in_longitude,
          a.check_out_latitude AS check_out_latitude,
          a.check_out_longitude AS check_out_longitude
        FROM users u
        LEFT JOIN attendance a
          ON a.user_id = u.id
          AND a.work_date = ?
        WHERE LOWER(TRIM(u.role)) IN
          ('employee', 'nhanvien', 'nhân viên')
        ORDER BY u.full_name COLLATE NOCASE ASC
        ''',
        [_dateString],
      );

      if (!mounted) return;

      setState(() {
        _records = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể tải báo cáo: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  bool _hasCheckedIn(Map<String, Object?> record) {
    final value = record['check_in'];
    return value != null && value.toString().trim().isNotEmpty;
  }

  bool _hasCheckedOut(Map<String, Object?> record) {
    final value = record['check_out'];
    return value != null && value.toString().trim().isNotEmpty;
  }

  String _statusOf(Map<String, Object?> record) {
    if (!_hasCheckedIn(record)) {
      return 'Chưa chấm công';
    }

    if (!_hasCheckedOut(record)) {
      return 'Chưa chấm công ra';
    }

    return 'Hoàn thành';
  }

  // Áp dụng tìm kiếm và bộ lọc trạng thái.
  List<Map<String, Object?>> get _filteredRecords {
    final keyword = _searchText.trim().toLowerCase();

    return _records.where((record) {
      final name = (record['full_name'] ?? '').toString().toLowerCase();
      final username = (record['username'] ?? '').toString().toLowerCase();

      final matchesSearch =
          keyword.isEmpty ||
          name.contains(keyword) ||
          username.contains(keyword);

      final status = _statusOf(record);

      final matchesStatus =
          _selectedStatus == 'Tất cả' ||
          (_selectedStatus == 'Chưa chấm công' && status == 'Chưa chấm công') ||
          (_selectedStatus == 'Chưa chấm công ra' &&
              status == 'Chưa chấm công ra') ||
          (_selectedStatus == 'Hoàn thành' && status == 'Hoàn thành');

      return matchesSearch && matchesStatus;
    }).toList();
  }

  String _formatTime(Object? value) {
    if (value == null || value.toString().trim().isEmpty) {
      return 'Chưa có';
    }

    final text = value.toString().trim();

    if (text.contains(' ')) {
      final parts = text.split(' ');
      return parts.last;
    }

    return text;
  }

  String _formatCoordinate(Object? value) {
    if (value == null || value.toString().trim().isEmpty) {
      return 'Chưa có';
    }

    final number = double.tryParse(value.toString());

    return number == null ? value.toString() : number.toStringAsFixed(6);
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Chọn ngày thống kê',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
    );

    if (selected == null || !mounted) return;

    setState(() => _selectedDate = selected);
    await _loadReport();
  }

  // Xuất báo cáo Excel.
  Future<void> _exportToExcel() async {
    if (_isLoading || _isExporting) return;

    final records = _filteredRecords;

    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu để xuất Excel.')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final excel = Excel.createExcel();
      final sheet = excel['BaoCaoChamCong'];

      // Tiêu đề báo cáo.
      sheet.appendRow([TextCellValue('BAO CAO CHAM CONG')]);

      sheet.appendRow([
        TextCellValue('Ngay thong ke'),
        TextCellValue(_dateString),
      ]);

      sheet.appendRow([
        TextCellValue('Tong so nhan vien trong bao cao'),
        IntCellValue(records.length),
      ]);

      sheet.appendRow([
        TextCellValue('STT'),
        TextCellValue('Ho va ten'),
        TextCellValue('Tai khoan'),
        TextCellValue('Trang thai'),
        TextCellValue('Gio vao'),
        TextCellValue('Gio ra'),
        TextCellValue('Vi do vao'),
        TextCellValue('Kinh do vao'),
        TextCellValue('Vi do ra'),
        TextCellValue('Kinh do ra'),
      ]);

      for (var i = 0; i < records.length; i++) {
        final record = records[i];

        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue((record['full_name'] ?? '').toString()),
          TextCellValue((record['username'] ?? '').toString()),
          TextCellValue(_statusOf(record)),
          TextCellValue(_formatTime(record['check_in'])),
          TextCellValue(_formatTime(record['check_out'])),
          TextCellValue(_formatCoordinate(record['check_in_latitude'])),
          TextCellValue(_formatCoordinate(record['check_in_longitude'])),
          TextCellValue(_formatCoordinate(record['check_out_latitude'])),
          TextCellValue(_formatCoordinate(record['check_out_longitude'])),
        ]);
      }

      final bytes = excel.encode();

      if (bytes == null) {
        throw Exception('Không thể tạo dữ liệu Excel.');
      }

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/BaoCaoChamCong_$_dateString.xlsx');

      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Báo cáo chấm công ngày $_dateString',
          subject: 'Báo cáo chấm công ngày $_dateString',
        ),
      );

      if (!mounted) return;

      if (result.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File Excel đã tạo tại: ${file.path}'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Xuất Excel thất bại: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // Hiển thị tọa độ GPS.
  void _showLocation(Map<String, Object?> record, bool isCheckIn) {
    final latitude =
        record[isCheckIn ? 'check_in_latitude' : 'check_out_latitude'];
    final longitude =
        record[isCheckIn ? 'check_in_longitude' : 'check_out_longitude'];

    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có tọa độ GPS cho lần chấm công này.'),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isCheckIn ? 'GPS chấm công vào' : 'GPS chấm công ra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nhân viên: ${record['full_name'] ?? ''}'),
            const SizedBox(height: 12),
            Text('Vĩ độ: ${_formatCoordinate(latitude)}'),
            Text('Kinh độ: ${_formatCoordinate(longitude)}'),
            const SizedBox(height: 8),
            const Text(
              'Tọa độ này được đọc từ SQLite. '
              'Địa chỉ đường phố chưa được xác định.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
        child: Column(
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    IconData icon;

    switch (status) {
      case 'Hoàn thành':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'Chưa chấm công ra':
        color = Colors.orange;
        icon = Icons.pending_actions;
        break;
      default:
        color = Colors.grey;
        icon = Icons.event_busy;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _filteredRecords;

    final totalEmployees = _records.length;
    final checkedInCount = _records.where(_hasCheckedIn).length;
    final checkedOutCount = _records.where(_hasCheckedOut).length;
    final notCheckedInCount = totalEmployees - checkedInCount;

    final percentage = totalEmployees == 0
        ? 0.0
        : checkedInCount / totalEmployees;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo chấm công'),
        actions: [
          IconButton(
            tooltip: 'Xuất Excel',
            onPressed: _isLoading || _isExporting ? null : _exportToExcel,
            icon: _isExporting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Tải lại báo cáo',
            onPressed: _isLoading ? null : _loadReport,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  InkWell(
                    onTap: _chooseDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Ngày thống kê: $_dateString',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Nhân viên',
                          value: totalEmployees,
                          icon: Icons.people,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Đã vào',
                          value: checkedInCount,
                          icon: Icons.login,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Đã ra',
                          value: checkedOutCount,
                          icon: Icons.logout,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Chưa vào',
                          value: notCheckedInCount,
                          icon: Icons.person_off,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tỷ lệ chấm công vào',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: percentage,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(percentage * 100).toStringAsFixed(1)}% '
                            '($checkedInCount/$totalEmployees nhân viên)',
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm theo tên hoặc tài khoản...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchText.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Xóa tìm kiếm',
                              onPressed: () {
                                setState(() => _searchText = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _searchText = value);
                    },
                  ),

                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    decoration: InputDecoration(
                      labelText: 'Lọc trạng thái',
                      prefixIcon: const Icon(Icons.filter_list),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Tất cả',
                        child: Text('Tất cả nhân viên'),
                      ),
                      DropdownMenuItem(
                        value: 'Chưa chấm công',
                        child: Text('Chưa chấm công vào'),
                      ),
                      DropdownMenuItem(
                        value: 'Chưa chấm công ra',
                        child: Text('Đã vào - chưa ra'),
                      ),
                      DropdownMenuItem(
                        value: 'Hoàn thành',
                        child: Text('Đã vào và đã ra'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedStatus = value);
                      }
                    },
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Danh sách nhân viên',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${records.length} người',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (records.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Column(
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('Không có nhân viên phù hợp.'),
                        ],
                      ),
                    )
                  else
                    ...records.map((record) {
                      final checkedIn = _hasCheckedIn(record);
                      final checkedOut = _hasCheckedOut(record);
                      final status = _statusOf(record);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const CircleAvatar(child: Icon(Icons.person)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (record['full_name'] ?? 'Chưa có tên')
                                              .toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tài khoản: '
                                          '${record['username'] ?? ''}',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildStatusChip(status),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                children: [
                                  const Icon(Icons.login, color: Colors.green),
                                  const SizedBox(width: 8),
                                  const Text('Giờ vào'),
                                  const Spacer(),
                                  Flexible(
                                    child: Text(
                                      _formatTime(record['check_in']),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.logout,
                                    color: Colors.redAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Giờ ra'),
                                  const Spacer(),
                                  Flexible(
                                    child: Text(
                                      _formatTime(record['check_out']),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: checkedIn
                                        ? () => _showLocation(record, true)
                                        : null,
                                    icon: const Icon(Icons.location_on),
                                    label: const Text('GPS vào'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: checkedOut
                                        ? () => _showLocation(record, false)
                                        : null,
                                    icon: const Icon(Icons.location_on),
                                    label: const Text('GPS ra'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
