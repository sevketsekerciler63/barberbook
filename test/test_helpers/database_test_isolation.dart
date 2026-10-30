import 'dart:io';

import 'package:berber_randevu/services/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseTestIsolation {
  Directory? _directory;

  String get databasePath => p.join(_directory!.path, 'barberbook.db');

  Future<void> setUp() async {
    await DatabaseService.instance.closeDatabase();
    _directory = await Directory.systemTemp.createTemp('barber_database_test_');
    await databaseFactory.setDatabasesPath(_directory!.path);
  }

  Future<void> tearDown() async {
    await DatabaseService.instance.closeDatabase();
    final directory = _directory;
    _directory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
