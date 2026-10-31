import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/backup_preview.dart';
import 'database_service.dart';

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  static const _archiveExtension = '.zip';
  static const _manifestPath = 'manifest.json';
  static const _databaseArchivePath = 'database/barberbook.db';
  static const _format = 'barberbook_backup';
  static const _formatVersion = 1;
  static const _maxArchiveEntries = 1000;
  static const _maxArchiveBytes = 200 * 1024 * 1024;

  Future<String> _databasePath() async =>
      path.join(await getDatabasesPath(), 'barberbook.db');

  Future<Directory> _photosDirectory() async =>
      Directory(path.join(await getDatabasesPath(), 'photos'));

  Future<Directory> _backupDirectory() async {
    final directory = Directory(path.join(await getDatabasesPath(), 'backups'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _stagingDirectory(String purpose) async {
    final directory = Directory(
      path.join(
        await getDatabasesPath(),
        'backup_staging',
        '${purpose}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> createBackup() async {
    await DatabaseService.instance.closeDatabase();
    final source = File(await _databasePath());
    if (!await source.exists()) {
      await DatabaseService.instance.database;
      await DatabaseService.instance.closeDatabase();
    }

    try {
      final archive = Archive();
      final databaseBytes = await source.readAsBytes();
      archive.addFile(
        ArchiveFile(_databaseArchivePath, databaseBytes.length, databaseBytes),
      );

      final photos = await _managedPhotoEntries(source);
      for (final photo in photos) {
        archive.addFile(
          ArchiveFile(photo.archivePath, photo.bytes.length, photo.bytes),
        );
      }
      final manifestBytes = utf8.encode(
        jsonEncode({
          'format': _format,
          'formatVersion': _formatVersion,
          'database': _databaseArchivePath,
          'photos': [for (final photo in photos) photo.toJson()],
        }),
      );
      archive.addFile(
        ArchiveFile(_manifestPath, manifestBytes.length, manifestBytes),
      );

      final directory = await _backupDirectory();
      final baseName = 'barberbook_${_stamp()}';
      var target = File(path.join(directory.path, '$baseName.zip'));
      var duplicateIndex = 1;
      while (await target.exists()) {
        target = File(
          path.join(directory.path, '${baseName}_$duplicateIndex.zip'),
        );
        duplicateIndex++;
      }
      final encoded = ZipEncoder().encodeBytes(archive);
      await target.writeAsBytes(encoded, flush: true);
      return target;
    } finally {
      await DatabaseService.instance.database;
    }
  }

  Future<List<_PhotoEntry>> _managedPhotoEntries(File database) async {
    Database? candidate;
    try {
      candidate = await openDatabase(
        database.path,
        readOnly: true,
        singleInstance: false,
      );
      final rows = await candidate.rawQuery('''
        SELECT photoPath FROM customers WHERE photoPath IS NOT NULL AND photoPath != ''
        UNION
        SELECT photoPath FROM customer_photos WHERE photoPath IS NOT NULL AND photoPath != ''
      ''');
      final photosDirectory = await _photosDirectory();
      final entries = <_PhotoEntry>[];
      final seenPaths = <String>{};
      for (final row in rows) {
        final databasePath = row['photoPath'] as String?;
        if (databasePath == null ||
            !path.isWithin(photosDirectory.path, databasePath) ||
            !seenPaths.add(databasePath)) {
          continue;
        }
        final photo = File(databasePath);
        if (!await photo.exists()) continue;
        final bytes = await photo.readAsBytes();
        final fileName = path.basename(databasePath);
        entries.add(
          _PhotoEntry(
            databasePath: databasePath,
            archivePath: 'photos/$fileName',
            sha256: sha256.convert(bytes).toString(),
            bytes: bytes,
          ),
        );
      }
      return entries;
    } finally {
      await candidate?.close();
    }
  }

  Future<List<File>> listBackups() async {
    final directory = await _backupDirectory();
    final files = await directory
        .list()
        .where(
          (item) =>
              item is File &&
              (item.path.endsWith(_archiveExtension) ||
                  item.path.endsWith('.db')),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> validateBackup(File backup) async {
    if (!await backup.exists() || await backup.length() == 0) {
      throw StateError('Yedek dosyası geçersiz.');
    }

    if (await _isZip(backup)) {
      final archive = await _readArchive(backup);
      final staging = await _stagingDirectory('validate');
      try {
        final databaseFile = File(path.join(staging.path, 'barberbook.db'));
        await databaseFile.writeAsBytes(archive.databaseBytes, flush: true);
        await _validateDatabase(databaseFile);
        await _validateArchivePhotoReferences(databaseFile, archive.photos);
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
      return;
    }

    await _validateDatabase(backup);
  }

  Future<bool> _isZip(File file) async {
    final input = await file.open();
    try {
      final header = await input.read(4);
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4b &&
          (header[2] == 0x03 || header[2] == 0x05 || header[2] == 0x07) &&
          (header[3] == 0x04 || header[3] == 0x06 || header[3] == 0x08);
    } finally {
      await input.close();
    }
  }

  Future<_ArchiveBackup> _readArchive(File backup) async {
    try {
      final bytes = await backup.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      if (archive.files.length > _maxArchiveEntries) {
        throw StateError('Yedek arşivi çok fazla dosya içeriyor.');
      }
      final files = <String, List<int>>{};
      var totalSize = 0;
      for (final file in archive.files) {
        if (!file.isFile ||
            !_isSafeArchivePath(file.name) ||
            files.containsKey(file.name)) {
          throw StateError('Yedek arşivinin dosya yapısı geçersiz.');
        }
        final content = file.content;
        totalSize += content.length;
        if (totalSize > _maxArchiveBytes) {
          throw StateError('Yedek arşivi çok büyük.');
        }
        files[file.name] = content;
      }

      final manifestBytes = files[_manifestPath];
      final databaseBytes = files[_databaseArchivePath];
      if (manifestBytes == null || databaseBytes == null) {
        throw StateError('Yedek arşivi gerekli dosyaları içermiyor.');
      }
      final decodedManifest = jsonDecode(utf8.decode(manifestBytes));
      if (decodedManifest is! Map<String, dynamic> ||
          decodedManifest['format'] != _format ||
          decodedManifest['formatVersion'] != _formatVersion ||
          decodedManifest['database'] != _databaseArchivePath ||
          decodedManifest['photos'] is! List) {
        throw StateError('Yedek arşivi tanınan bir BarberBook yedeği değil.');
      }

      final photos = <_PhotoEntry>[];
      final photoPaths = <String>{};
      final archivePaths = <String>{};
      for (final value in decodedManifest['photos'] as List<dynamic>) {
        if (value is! Map) throw StateError('Yedek fotoğraf bilgisi geçersiz.');
        final databasePath = value['databasePath'];
        final archivePath = value['archivePath'];
        final checksum = value['sha256'];
        if (databasePath is! String ||
            archivePath is! String ||
            checksum is! String ||
            !archivePath.startsWith('photos/') ||
            !_isSafeArchivePath(archivePath) ||
            path.posix.dirname(archivePath) != 'photos' ||
            !photoPaths.add(databasePath) ||
            !archivePaths.add(archivePath)) {
          throw StateError('Yedek fotoğraf bilgisi geçersiz.');
        }
        final photoBytes = files[archivePath];
        if (photoBytes == null ||
            sha256.convert(photoBytes).toString() != checksum) {
          throw StateError(
            'Yedekteki fotoğraf bütünlük kontrolünden geçemedi.',
          );
        }
        photos.add(
          _PhotoEntry(
            databasePath: databasePath,
            archivePath: archivePath,
            sha256: checksum,
            bytes: photoBytes,
          ),
        );
      }
      if (files.keys.any(
        (entry) =>
            entry != _manifestPath &&
            entry != _databaseArchivePath &&
            !archivePaths.contains(entry),
      )) {
        throw StateError('Yedek arşivinde beklenmeyen dosyalar var.');
      }
      return _ArchiveBackup(databaseBytes: databaseBytes, photos: photos);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('Yedek geçerli bir ZIP arşivi değil.');
    }
  }

  bool _isSafeArchivePath(String value) =>
      value.isNotEmpty &&
      !value.contains('\\') &&
      !value.startsWith('/') &&
      !value.contains('..') &&
      path.posix.normalize(value) == value;

  Future<void> _validateDatabase(File backup) async {
    Database? candidate;
    try {
      candidate = await openDatabase(
        backup.path,
        readOnly: true,
        singleInstance: false,
      );
      final integrity = await candidate.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw StateError('Yedek veritabanı bütünlük kontrolünden geçemedi.');
      }

      final version =
          Sqflite.firstIntValue(
            await candidate.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      if (version < 1 || version > 12) {
        throw StateError('Yedek şema sürümü desteklenmiyor: $version');
      }

      final tableRows = await candidate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = tableRows.map((row) => row['name']).toSet();
      final requiredTables = <String>{'customers', 'appointments'};
      if (version >= 4) requiredTables.add('services');
      if (version >= 5) {
        requiredTables.addAll({'working_hours', 'closed_time_blocks'});
      }
      if (version >= 6) requiredTables.add('payments');
      if (version >= 7) requiredTables.add('payment_transactions');
      if (version >= 9) requiredTables.add('customer_photos');
      if (version >= 10) requiredTables.add('hairstyle_templates');
      if (version >= 11) requiredTables.add('shop_settings');
      if (!tables.containsAll(requiredTables)) {
        throw StateError('Yedek gerekli uygulama tablolarını içermiyor.');
      }

      final foreignKeyErrors = await candidate.rawQuery(
        'PRAGMA foreign_key_check',
      );
      if (foreignKeyErrors.isNotEmpty) {
        throw StateError('Yedekte ilişki bütünlüğü hataları bulundu.');
      }
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('Yedek geçerli bir SQLite veritabanı değil.');
    } finally {
      await candidate?.close();
    }
  }

  Future<void> _validateArchivePhotoReferences(
    File database,
    List<_PhotoEntry> photos,
  ) async {
    Database? candidate;
    try {
      candidate = await openDatabase(
        database.path,
        readOnly: true,
        singleInstance: false,
      );
      final columns = await candidate.rawQuery('PRAGMA table_info(customers)');
      final hasPhotoPath = columns.any(
        (column) => column['name'] == 'photoPath',
      );
      if (!hasPhotoPath) {
        if (photos.isNotEmpty) {
          throw StateError(
            'Yedekte fotoğraf alanı olmayan bir veritabanı var.',
          );
        }
        return;
      }
      final rows = await candidate.rawQuery('''
        SELECT photoPath FROM customers WHERE photoPath IS NOT NULL AND photoPath != ''
        UNION
        SELECT photoPath FROM customer_photos WHERE photoPath IS NOT NULL AND photoPath != ''
      ''');
      final referencedPaths = rows
          .map((row) => row['photoPath'] as String)
          .toSet();
      final archivedPaths = photos.map((photo) => photo.databasePath).toSet();
      if (!referencedPaths.containsAll(archivedPaths) ||
          !archivedPaths.containsAll(referencedPaths)) {
        throw StateError(
          'Yedekteki fotoğraf kayıtları veritabanıyla eşleşmiyor.',
        );
      }
    } finally {
      await candidate?.close();
    }
  }

  Future<BackupPreview> previewBackup(File backup) async {
    await validateBackup(backup);
    final staging = await _stagingDirectory('preview');
    Database? candidate;
    try {
      final databaseFile = await _databaseFileForBackup(backup, staging);
      candidate = await openDatabase(
        databaseFile.path,
        readOnly: true,
        singleInstance: false,
      );
      final tables = (await candidate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']).toSet();

      Future<int> count(String table) async {
        if (!tables.contains(table)) return 0;
        return Sqflite.firstIntValue(
              await candidate!.rawQuery('SELECT COUNT(*) FROM $table'),
            ) ??
            0;
      }

      return BackupPreview(
        schemaVersion: await candidate.getVersion(),
        customerCount: await count('customers'),
        appointmentCount: await count('appointments'),
        serviceCount: await count('services'),
        paymentCount: await count('payments'),
        transactionCount: await count('payment_transactions'),
      );
    } finally {
      await candidate?.close();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<File> _databaseFileForBackup(File backup, Directory staging) async {
    if (!await _isZip(backup)) return backup;
    final archive = await _readArchive(backup);
    final databaseFile = File(path.join(staging.path, 'barberbook.db'));
    await databaseFile.writeAsBytes(archive.databaseBytes, flush: true);
    return databaseFile;
  }

  Future<BackupRestoreResult> restoreBackup(
    File backup, {
    Future<void> Function()? synchronizeAlarms,
  }) async {
    await validateBackup(backup);
    final isArchive = await _isZip(backup);
    final safetyBackup = await createBackup();
    await DatabaseService.instance.closeDatabase();
    try {
      await _restoreBackupContents(backup);
      await DatabaseService.instance.database;
      if (!isArchive) await _clearLegacyPhotoReferences();
    } catch (_) {
      await DatabaseService.instance.closeDatabase();
      try {
        await _restoreBackupContents(safetyBackup);
        await DatabaseService.instance.database;
      } catch (_) {
        // The original restore error remains more useful to the caller.
      }
      rethrow;
    }
    // The data is already restored. An OS alarm failure must not roll it back.
    if (synchronizeAlarms != null) {
      try {
        await synchronizeAlarms();
      } catch (_) {
        return const BackupRestoreResult(alarmsSynchronized: false);
      }
    }
    return BackupRestoreResult(
      alarmsSynchronized: synchronizeAlarms == null ? null : true,
    );
  }

  Future<void> _restoreBackupContents(File backup) async {
    final archive = await _isZip(backup) ? await _readArchive(backup) : null;
    final staging = await _stagingDirectory('restore');
    try {
      final stagedDatabase = File(path.join(staging.path, 'barberbook.db'));
      if (archive == null) {
        await backup.copy(stagedDatabase.path);
      } else {
        await stagedDatabase.writeAsBytes(archive.databaseBytes, flush: true);
        final stagedPhotos = Directory(path.join(staging.path, 'photos'));
        await stagedPhotos.create(recursive: true);
        for (final photo in archive.photos) {
          await File(
            path.join(stagedPhotos.path, path.basename(photo.archivePath)),
          ).writeAsBytes(photo.bytes, flush: true);
        }
      }

      final targetDatabase = File(await _databasePath());
      // File.copy does not overwrite on Windows; remove the closed active DB
      // before replacing it with the already validated restore candidate.
      if (await targetDatabase.exists()) {
        await targetDatabase.delete();
      }
      await stagedDatabase.copy(targetDatabase.path);
      if (archive != null) {
        final targetPhotos = await _photosDirectory();
        if (await targetPhotos.exists()) {
          await targetPhotos.delete(recursive: true);
        }
        await targetPhotos.create(recursive: true);
        final stagedPhotos = Directory(path.join(staging.path, 'photos'));
        await for (final photo in stagedPhotos.list()) {
          if (photo is File) {
            await photo.copy(
              path.join(targetPhotos.path, path.basename(photo.path)),
            );
          }
        }
        await _rewriteRestoredPhotoPaths(
          targetDatabase,
          targetPhotos,
          archive.photos,
        );
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _clearLegacyPhotoReferences() async {
    final targetPhotos = await _photosDirectory();
    if (await targetPhotos.exists()) {
      await targetPhotos.delete(recursive: true);
    }

    final database = await DatabaseService.instance.database;
    await database.transaction((txn) async {
      final customerColumns = await txn.rawQuery(
        'PRAGMA table_info(customers)',
      );
      if (customerColumns.any((column) => column['name'] == 'photoPath')) {
        await txn.update('customers', {'photoPath': null});
      }

      final tableRows = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'customer_photos'",
      );
      if (tableRows.isNotEmpty) {
        await txn.delete('customer_photos');
      }
    });
  }

  Future<void> _rewriteRestoredPhotoPaths(
    File database,
    Directory photosDirectory,
    List<_PhotoEntry> photos,
  ) async {
    if (photos.isEmpty) return;
    Database? restored;
    try {
      restored = await openDatabase(
        database.path,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      );
      final batch = restored.batch();
      for (final photo in photos) {
        final restoredPath = path.join(
          photosDirectory.path,
          path.basename(photo.archivePath),
        );
        batch.update(
          'customers',
          {'photoPath': restoredPath},
          where: 'photoPath = ?',
          whereArgs: [photo.databasePath],
        );
        batch.update(
          'customer_photos',
          {'photoPath': restoredPath},
          where: 'photoPath = ?',
          whereArgs: [photo.databasePath],
        );
      }
      await batch.commit(noResult: true);
    } finally {
      await restored?.close();
    }
  }

  String _stamp() {
    final now = DateTime.now();
    return [
      now.year.toString().padLeft(4, '0'),
      now.month.toString().padLeft(2, '0'),
      now.day.toString().padLeft(2, '0'),
      '_',
      now.hour.toString().padLeft(2, '0'),
      now.minute.toString().padLeft(2, '0'),
      now.second.toString().padLeft(2, '0'),
      '_',
      now.microsecond.toString().padLeft(6, '0'),
    ].join();
  }
}

class _ArchiveBackup {
  const _ArchiveBackup({required this.databaseBytes, required this.photos});

  final List<int> databaseBytes;
  final List<_PhotoEntry> photos;
}

class _PhotoEntry {
  const _PhotoEntry({
    required this.databasePath,
    required this.archivePath,
    required this.sha256,
    required this.bytes,
  });

  final String databasePath;
  final String archivePath;
  final String sha256;
  final List<int> bytes;

  Map<String, String> toJson() => {
    'databasePath': databasePath,
    'archivePath': archivePath,
    'sha256': sha256,
  };
}

class BackupRestoreResult {
  /// Null when no device synchronization was requested (e.g. database-only use).
  final bool? alarmsSynchronized;
  const BackupRestoreResult({required this.alarmsSynchronized});
}
