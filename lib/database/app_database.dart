import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasePath = await getDatabasesPath();
    final pathName = join(databasePath, 'phungchimy_nhom7.db');

    _database = await openDatabase(
      pathName,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            full_name TEXT NOT NULL,
            username TEXT NOT NULL UNIQUE,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'employee',
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            check_in TEXT,
            check_out TEXT,
            work_date TEXT NOT NULL,
            check_in_latitude REAL,
            check_in_longitude REAL,
            check_out_latitude REAL,
            check_out_longitude REAL,
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''');

        await _createFaceProfilesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE attendance ADD COLUMN check_in_latitude REAL',
          );
          await db.execute(
            'ALTER TABLE attendance ADD COLUMN check_in_longitude REAL',
          );
          await db.execute(
            'ALTER TABLE attendance ADD COLUMN check_out_latitude REAL',
          );
          await db.execute(
            'ALTER TABLE attendance ADD COLUMN check_out_longitude REAL',
          );
        }

        if (oldVersion < 3) {
          await _createFaceProfilesTable(db);
        }
      },
    );

    return _database!;
  }

  static Future<void> _createFaceProfilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS face_profiles (
        user_id INTEGER PRIMARY KEY,
        face_embedding TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
          ON DELETE CASCADE
      )
    ''');
  }

  // =========================
  // QUẢN LÝ TÀI KHOẢN
  // =========================

  Future<int> createUser(Map<String, Object?> user) async {
    final db = await database;

    return db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<Map<String, Object?>?> findUserByUsername(String username) async {
    final db = await database;

    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username.trim()],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  Future<bool> usernameExists(String username) async {
    final db = await database;

    final result = await db.query(
      'users',
      columns: ['id'],
      where: 'username = ?',
      whereArgs: [username.trim()],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<bool> emailExists(String email) async {
    final db = await database;

    final result = await db.query(
      'users',
      columns: ['id'],
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> getUsers() async {
    final db = await database;
    return db.query('users', orderBy: 'id DESC');
  }

  // =========================
  // HỒ SƠ NHẬN DIỆN KHUÔN MẶT
  // =========================

  /// Lưu hoặc cập nhật vector khuôn mặt của một nhân viên.
  ///
  /// faceEmbedding phải được tạo bởi mô hình nhận diện khuôn mặt.
  /// Không truyền tọa độ từ ML Kit Face Detection hoặc đường dẫn ảnh.
  Future<void> saveFaceProfile({
    required int userId,
    required List<double> faceEmbedding,
  }) async {
    if (userId <= 0) {
      throw ArgumentError('ID nhân viên không hợp lệ.');
    }

    if (faceEmbedding.isEmpty) {
      throw ArgumentError('Vector khuôn mặt không được để trống.');
    }

    if (faceEmbedding.any((value) => !value.isFinite)) {
      throw ArgumentError('Vector chứa giá trị số không hợp lệ.');
    }

    final db = await database;

    await db.transaction((txn) async {
      final users = await txn.query(
        'users',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (users.isEmpty) {
        throw Exception('Không tìm thấy nhân viên có ID $userId.');
      }

      await txn.insert('face_profiles', {
        'user_id': userId,
        'face_embedding': jsonEncode(faceEmbedding),
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Lấy hồ sơ khuôn mặt đầy đủ.
  Future<Map<String, Object?>?> getFaceProfile(int userId) async {
    final db = await database;

    final result = await db.query(
      'face_profiles',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  /// Đọc vector khuôn mặt để sử dụng khi xác minh.
  Future<List<double>?> getFaceEmbedding(int userId) async {
    final profile = await getFaceProfile(userId);

    if (profile == null) return null;

    final rawData = profile['face_embedding'];

    if (rawData is! String) {
      throw const FormatException(
        'Dữ liệu vector khuôn mặt không đúng định dạng.',
      );
    }

    final dynamic decoded;

    try {
      decoded = jsonDecode(rawData);
    } on FormatException {
      throw const FormatException('Không thể đọc vector khuôn mặt từ SQLite.');
    }

    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException('Vector khuôn mặt không hợp lệ.');
    }

    final embedding = <double>[];

    for (final value in decoded) {
      if (value is! num || !value.toDouble().isFinite) {
        throw const FormatException(
          'Vector khuôn mặt chứa dữ liệu không hợp lệ.',
        );
      }

      embedding.add(value.toDouble());
    }

    return embedding;
  }

  /// Kiểm tra nhân viên đã đăng ký khuôn mặt hay chưa.
  Future<bool> hasFaceProfile(int userId) async {
    final profile = await getFaceProfile(userId);
    return profile != null;
  }

  /// Xóa hồ sơ khuôn mặt, không xóa tài khoản hoặc lịch sử chấm công.
  Future<int> deleteFaceProfile(int userId) async {
    final db = await database;

    return db.delete(
      'face_profiles',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
