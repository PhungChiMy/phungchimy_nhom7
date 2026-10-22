
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../database/app_database.dart';
import 'admin_attendance_report_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, Object?>> users = [];
  bool isLoading = true;
  String searchText = '';

  static const List<String> roles = ['admin', 'employee', 'customer'];

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  // Băm mật khẩu SHA-256.
  // Giữ nguyên cách xác thực đang dùng trong dự án.
  String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Future<void> loadUsers() async {
    if (mounted) {
      setState(() => isLoading = true);
    }

    try {
      final result = await AppDatabase.instance.getUsers();

      if (!mounted) return;

      setState(() {
        users = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải tài khoản: $e')),
      );
    }
  }

  String roleName(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Quản trị viên';
      case 'customer':
        return 'Khách hàng';
      default:
        return 'Nhân viên';
    }
  }

  List<Map<String, Object?>> get filteredUsers {
    final keyword = searchText.trim().toLowerCase();

    if (keyword.isEmpty) return users;

    return users.where((user) {
      final name = user['full_name']?.toString().toLowerCase() ?? '';
      final username = user['username']?.toString().toLowerCase() ?? '';
      final email = user['email']?.toString().toLowerCase() ?? '';

      return name.contains(keyword) ||
          username.contains(keyword) ||
          email.contains(keyword);
    }).toList();
  }

  Future<void> showUserForm({Map<String, Object?>? user}) async {
    final isEditing = user != null;

    final nameController = TextEditingController(
      text: user?['full_name']?.toString() ?? '',
    );
    final usernameController = TextEditingController(
      text: user?['username']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: user?['email']?.toString() ?? '',
    );
    final passwordController = TextEditingController();

    final formKey = GlobalKey<FormState>();

    String selectedRole = roles.contains(user?['role']?.toString())
        ? user!['role'].toString()
        : 'employee';

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(isEditing ? 'Sửa tài khoản' : 'Thêm tài khoản'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Họ và tên',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Vui lòng nhập họ tên.';
                              }
                              if (value.trim().length < 2) {
                                return 'Họ tên cần ít nhất 2 ký tự.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: usernameController,
                            enabled: !isEditing,
                            decoration: InputDecoration(
                              labelText: 'Tên đăng nhập',
                              prefixIcon: const Icon(Icons.account_circle),
                              border: const OutlineInputBorder(),
                              helperText: isEditing
                                  ? 'Không thể sửa tên đăng nhập.'
                                  : 'Không sử dụng khoảng trắng.',
                            ),
                            validator: (value) {
                              final username = value?.trim() ?? '';

                              if (username.isEmpty) {
                                return 'Vui lòng nhập tên đăng nhập.';
                              }

                              if (username.contains(' ')) {
                                return 'Tên đăng nhập không được có khoảng trắng.';
                              }

                              if (username.length < 3) {
                                return 'Tên đăng nhập cần ít nhất 3 ký tự.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final email =
                                  value?.trim().toLowerCase() ?? '';

                              if (email.isEmpty) {
                                return 'Vui lòng nhập email.';
                              }

                              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(email)) {
                                return 'Email không hợp lệ.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: passwordController,
                            obscureText: true,
                            autofillHints: const [],
                            decoration: InputDecoration(
                              labelText: isEditing
                                  ? 'Mật khẩu mới (không bắt buộc)'
                                  : 'Mật khẩu',
                              prefixIcon: const Icon(Icons.lock),
                              border: const OutlineInputBorder(),
                              helperText: isEditing
                                  ? 'Để trống nếu không muốn đổi mật khẩu.'
                                  : 'Mật khẩu cần ít nhất 6 ký tự.',
                            ),
                            validator: (value) {
                              final password = value ?? '';

                              if (!isEditing && password.isEmpty) {
                                return 'Vui lòng nhập mật khẩu.';
                              }

                              if (password.isNotEmpty &&
                                  password.length < 6) {
                                return 'Mật khẩu cần ít nhất 6 ký tự.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: selectedRole,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Quyền tài khoản',
                              prefixIcon: Icon(Icons.admin_panel_settings),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'admin',
                                child: Text('Quản trị viên'),
                              ),
                              DropdownMenuItem(
                                value: 'employee',
                                child: Text('Nhân viên'),
                              ),
                              DropdownMenuItem(
                                value: 'customer',
                                child: Text('Khách hàng'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedRole = value;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },
                    child: const Text('Hủy'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (formKey.currentState?.validate() ?? false) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Lưu'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result == true && mounted) {
        await saveUser(
          user: user,
          fullName: nameController.text.trim(),
          username: usernameController.text.trim(),
          email: emailController.text.trim().toLowerCase(),
          password: passwordController.text,
          role: selectedRole,
        );
      }
    } finally {
      nameController.dispose();
      usernameController.dispose();
      emailController.dispose();
      passwordController.dispose();
    }
  }

  Future<void> saveUser({
    required Map<String, Object?>? user,
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    final isEditing = user != null;

    try {
      final db = await AppDatabase.instance.database;

      // Kiểm tra email đã được tài khoản khác sử dụng hay chưa.
      final duplicateEmail = await db.query(
        'users',
        columns: ['id'],
        where: 'LOWER(email) = LOWER(?) AND id != ?',
        whereArgs: [email, isEditing ? user['id'] : -1],
        limit: 1,
      );

      if (duplicateEmail.isNotEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email này đã được tài khoản khác sử dụng.'),
          ),
        );
        return;
      }

      if (isEditing) {
        final data = <String, Object?>{
          'full_name': fullName,
          'email': email,
          'role': role,
        };

        if (password.isNotEmpty) {
          data['password_hash'] = hashPassword(password);
        }

        await db.update(
          'users',
          data,
          where: 'id = ?',
          whereArgs: [user['id']],
        );
      } else {
        // Kiểm tra tên đăng nhập trước khi tạo tài khoản.
        final duplicateUsername = await db.query(
          'users',
          columns: ['id'],
          where: 'LOWER(username) = LOWER(?)',
          whereArgs: [username],
          limit: 1,
        );

        if (duplicateUsername.isNotEmpty) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tên đăng nhập đã tồn tại. Vui lòng chọn tên khác.',
              ),
            ),
          );
          return;
        }

        await AppDatabase.instance.createUser({
          'full_name': fullName,
          'username': username,
          'email': email,
          'password_hash': hashPassword(password),
          'role': role,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      await loadUsers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Cập nhật tài khoản thành công.'
                : 'Tạo tài khoản thành công.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể lưu tài khoản. Hãy kiểm tra email, '
            'tên đăng nhập và cơ sở dữ liệu.\nChi tiết: $e',
          ),
        ),
      );
    }
  }

  Future<void> changeRole(
    Map<String, Object?> user,
    String newRole,
  ) async {
    if (!roles.contains(newRole)) return;

    try {
      final db = await AppDatabase.instance.database;

      await db.update(
        'users',
        {'role': newRole},
        where: 'id = ?',
        whereArgs: [user['id']],
      );

      await loadUsers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật quyền tài khoản.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật quyền: $e')),
      );
    }
  }

  Future<void> deleteUser(Map<String, Object?> user) async {
    final username = user['username']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? username;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận xóa tài khoản'),
          content: Text(
            'Bạn có chắc muốn xóa tài khoản "$username" '
            '($fullName) không?\n\n'
            'Thao tác này có thể bị từ chối nếu tài khoản có '
            'lịch sử chấm công liên kết.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.delete),
              label: const Text('Xóa tài khoản'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      final db = await AppDatabase.instance.database;

      await db.delete(
        'users',
        where: 'id = ?',
        whereArgs: [user['id']],
      );

      await loadUsers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa tài khoản thành công.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể xóa tài khoản. Có thể tài khoản đang có '
            'lịch sử chấm công liên kết.\nChi tiết: $e',
          ),
        ),
      );
    }
  }

  Widget buildUserCard(Map<String, Object?> user) {
    final username = user['username']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? username;
    final email = user['email']?.toString() ?? '';
    final role = user['role']?.toString() ?? 'employee';
    final createdAt = user['created_at']?.toString() ?? '';

    final avatarColor = role == 'admin'
        ? Colors.deepPurple
        : role == 'customer'
            ? Colors.teal
            : Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: avatarColor.withValues(alpha: 0.12),
                  foregroundColor: avatarColor,
                  radius: 25,
                  child: Icon(
                    role == 'admin'
                        ? Icons.admin_panel_settings
                        : role == 'customer'
                            ? Icons.person_outline
                            : Icons.badge,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text('Tên đăng nhập: $username'),
                      const SizedBox(height: 3),
                      Text('Email: $email'),
                      const SizedBox(height: 3),
                      Text('Quyền: ${roleName(role)}'),
                      if (createdAt.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Ngày tạo: ${createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('${user['id']}_$role'),
              initialValue: roles.contains(role) ? role : 'employee',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Thay đổi quyền tài khoản',
                prefixIcon: Icon(Icons.manage_accounts),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'admin',
                  child: Text('Quản trị viên'),
                ),
                DropdownMenuItem(
                  value: 'employee',
                  child: Text('Nhân viên'),
                ),
                DropdownMenuItem(
                  value: 'customer',
                  child: Text('Khách hàng'),
                ),
              ],
              onChanged: (newRole) {
                if (newRole != null && newRole != role) {
                  changeRole(user, newRole);
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showUserForm(user: user),
                    icon: const Icon(Icons.edit),
                    label: const Text('Sửa'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () => deleteUser(user),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xóa'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Mở màn hình báo cáo chấm công.
  void openAttendanceReport() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const AdminAttendanceReportScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedUsers = filteredUsers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý tài khoản'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: loadUsers,
            tooltip: 'Tải lại danh sách',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showUserForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Thêm tài khoản'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadUsers,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // NÚT MỚI: BÁO CÁO CHẤM CÔNG
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE3F2FD),
                        child: Icon(
                          Icons.assessment,
                          color: Colors.blue,
                        ),
                      ),
                      title: const Text(
                        'Báo cáo chấm công',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Xem giờ vào, giờ ra và vị trí GPS của nhân viên',
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                      ),
                      onTap: openAttendanceReport,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tổng số tài khoản
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.people),
                      ),
                      title: const Text('Tổng số tài khoản'),
                      subtitle: const Text('Tất cả vai trò'),
                      trailing: Text(
                        '${users.length}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tìm kiếm tài khoản
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Tìm tài khoản',
                      hintText: 'Nhập tên, tên đăng nhập hoặc email',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchText.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() => searchText = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() => searchText = value);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Danh sách tài khoản
                  if (displayedUsers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_search,
                            size: 56,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            users.isEmpty
                                ? 'Chưa có tài khoản nào.'
                                : 'Không tìm thấy tài khoản phù hợp.',
                            textAlign: TextAlign.center,
                          ),
                          if (users.isEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Nhấn "Thêm tài khoản" để tạo tài khoản mới.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    )
                  else ...[
                    Text(
                      'Đang hiển thị ${displayedUsers.length} / ${users.length} tài khoản',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    ...displayedUsers.map(buildUserCard),
                  ],
                ],
              ),
            ),
    );
  }
}
