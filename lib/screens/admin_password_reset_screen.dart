import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../database/app_database.dart';

class AdminPasswordResetScreen extends StatefulWidget {
  const AdminPasswordResetScreen({super.key});

  @override
  State<AdminPasswordResetScreen> createState() =>
      _AdminPasswordResetScreenState();
}

class _AdminPasswordResetScreenState extends State<AdminPasswordResetScreen> {
  final _usernameController = TextEditingController(text: 'admin01');
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  bool _hidePassword = true;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetPassword() async {
    if (_loading) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmController.text;

    if (username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showMessage('Vui lòng nhập đầy đủ thông tin.');
      return;
    }

    if (password.length < 8) {
      _showMessage('Mật khẩu mới phải có ít nhất 8 ký tự.');
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Hai mật khẩu không khớp.');
      return;
    }

    setState(() => _loading = true);

    try {
      final user = await AppDatabase.instance.findUserByUsername(username);

      if (user == null) {
        _showMessage('Không tìm thấy tài khoản $username.');
        return;
      }

      final role = user['role']?.toString().toLowerCase();

      if (role != 'admin') {
        _showMessage(
          'Tài khoản này không có quyền Admin. '
          'Mật khẩu chưa được thay đổi.',
        );
        return;
      }

      final db = await AppDatabase.instance.database;

      final updatedRows = await db.update(
        'users',
        {'password_hash': _hashPassword(password)},
        where: 'id = ? AND username = ?',
        whereArgs: [user['id'], username],
      );

      if (!mounted) return;

      if (updatedRows != 1) {
        _showMessage('Không cập nhật được mật khẩu.');
        return;
      }

      _passwordController.clear();
      _confirmController.clear();

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Đặt lại thành công'),
          content: const Text(
            'Mật khẩu của tài khoản admin01 đã được cập nhật. '
            'Hãy quay lại màn hình đăng nhập và dùng mật khẩu mới.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Quay lại đăng nhập'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage('Có lỗi xảy ra: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Khôi phục mật khẩu Admin')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.indigo,
                    size: 76,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ĐẶT LẠI MẬT KHẨU',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chỉ sử dụng cho tài khoản Admin của ứng dụng thử nghiệm.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _hidePassword,
                    autofillHints: const [],
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu mới',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _hidePassword = !_hidePassword;
                          });
                        },
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmController,
                    obscureText: _hidePassword,
                    decoration: const InputDecoration(
                      labelText: 'Xác nhận mật khẩu mới',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _resetPassword(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _resetPassword,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_reset),
                      label: Text(
                        _loading ? 'Đang xử lý...' : 'Đặt lại mật khẩu',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Mật khẩu phải có ít nhất 8 ký tự. '
                    'Tài khoản không có quyền Admin sẽ không được cập nhật.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
