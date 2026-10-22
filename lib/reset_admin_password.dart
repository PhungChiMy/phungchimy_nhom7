import 'dart:io';

import 'database/app_database.dart';

Future<void> main() async {
  stdout.writeln('======================================');
  stdout.writeln('   SMART ATTENDANCE - RESET ADMIN');
  stdout.writeln('======================================');

  const username = 'admin01';

  try {
    final user =
        await AppDatabase.instance.findUserByUsername(username);

    if (user == null) {
      stdout.writeln('Khong tim thay tai khoan $username.');
      exitCode = 1;
      return;
    }

    final role = user['role']?.toString().toLowerCase();

    if (role != 'admin') {
      stdout.writeln(
        'Tai khoan $username khong co quyen Admin. '
        'Khong thay doi du lieu.',
      );
      exitCode = 1;
      return;
    }

    stdout.writeln('Da xac nhan tai khoan Admin: $username');
    stdout.writeln(
      'Luu y: Chua thay doi mat khau hoac du lieu SQLite.',
    );
  } catch (e) {
    stdout.writeln('Loi: $e');
    exitCode = 1;
  }
}