import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../database/app_database.dart';

class AttendanceMapScreen extends StatefulWidget {
  const AttendanceMapScreen({super.key});

  @override
  State<AttendanceMapScreen> createState() => _AttendanceMapScreenState();
}

class _AttendanceMapScreenState extends State<AttendanceMapScreen> {
  bool _isLoading = true;
  String? _error;
  final List<_GpsPoint> _points = [];

  @override
  void initState() {
    super.initState();
    _loadGpsPoints();
  }

  double? _toDouble(Object? value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  Future<void> _loadGpsPoints() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('attendance');

      final points = <_GpsPoint>[];

      for (final row in rows) {
        final inLat = _toDouble(row['check_in_latitude']);
        final inLng = _toDouble(row['check_in_longitude']);
        final outLat = _toDouble(row['check_out_latitude']);
        final outLng = _toDouble(row['check_out_longitude']);

        if (_isValidCoordinate(inLat, inLng)) {
          points.add(
            _GpsPoint(
              position: LatLng(inLat!, inLng!),
              label: 'Chấm công vào',
              color: Colors.green,
              isCheckIn: true,
            ),
          );
        }

        if (_isValidCoordinate(outLat, outLng)) {
          points.add(
            _GpsPoint(
              position: LatLng(outLat!, outLng!),
              label: 'Chấm công ra',
              color: Colors.red,
              isCheckIn: false,
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _points
          ..clear()
          ..addAll(points);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Không đọc được dữ liệu GPS: $e';
        _isLoading = false;
      });
    }
  }

  bool _isValidCoordinate(double? lat, double? lng) {
    return lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  // Dịch vị trí HIỂN THỊ để hai dấu không che nhau.
  // Tọa độ GPS gốc trong SQLite không bị thay đổi.
  LatLng _displayPosition(_GpsPoint point) {
    const offset = 0.00008;

    if (point.isCheckIn) {
      return LatLng(
        point.position.latitude + offset,
        point.position.longitude - offset,
      );
    }

    return LatLng(
      point.position.latitude - offset,
      point.position.longitude + offset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _points.isNotEmpty
        ? _points.first.position
        : const LatLng(10.8231, 106.6297);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bản đồ chấm công GPS'),
        actions: [
          IconButton(
            tooltip: 'Tải lại GPS',
            onPressed: _loadGpsPoints,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _points.isEmpty
          ? const Center(
              child: Text(
                'Chưa có tọa độ GPS trong lịch sử chấm công.',
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _legend(Colors.green, 'GPS vào'),
                      _legend(Colors.red, 'GPS ra'),
                    ],
                  ),
                ),
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(initialCenter: center, initialZoom: 17),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.smart_attendance_app',
                      ),
                      MarkerLayer(
                        markers: _points.map((point) {
                          return Marker(
                            // Chỉ dịch dấu hiển thị.
                            point: _displayPosition(point),
                            width: 125,
                            height: 78,
                            child: GestureDetector(
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (dialogContext) {
                                    return AlertDialog(
                                      title: Text(point.label),
                                      content: Text(
                                        'GPS thực tế đã lưu:\n'
                                        'Vĩ độ: '
                                        '${point.position.latitude.toStringAsFixed(6)}\n'
                                        'Kinh độ: '
                                        '${point.position.longitude.toStringAsFixed(6)}',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('Đóng'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    color: point.color,
                                    size: 42,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: point.color),
                                    ),
                                    child: Text(
                                      point.isCheckIn ? 'GPS vào' : 'GPS ra',
                                      style: TextStyle(
                                        color: point.color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Tổng số vị trí GPS: ${_points.length}\n'
                    'Hai dấu có thể được dịch nhẹ để dễ quan sát; '
                    'tọa độ hiển thị khi nhấn dấu là tọa độ thực tế.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

class _GpsPoint {
  final LatLng position;
  final String label;
  final Color color;
  final bool isCheckIn;

  const _GpsPoint({
    required this.position,
    required this.label,
    required this.color,
    required this.isCheckIn,
  });
}
