import 'package:flutter/material.dart';

class CustomerScreen extends StatelessWidget {
  final String fullName;

  const CustomerScreen({super.key, required this.fullName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khách hàng'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.account_circle, color: Colors.blue, size: 70),
                  SizedBox(height: 12),
                  Text(
                    'SMART ATTENDANCE',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('Khu vực khách hàng'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.blue),
            title: const Text('Họ và tên'),
            subtitle: Text(fullName),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline, color: Colors.blue),
            title: Text('Thông tin'),
            subtitle: Text('Bạn đang đăng nhập bằng tài khoản khách hàng.'),
          ),
          const SizedBox(height: 20),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Chức năng dành cho khách hàng sẽ được bổ sung '
                'trong các bước tiếp theo.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
