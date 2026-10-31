import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/backup_preview.dart';
import 'database_service.dart';
import 'restore_file_transaction.dart';

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  static const _archiveExtension = '.zip';
  static const _manifestPath = 'manifest.json';
  static const _databaseArchivePath = 'database/barberbook.db';
  static const _format = 'barberbook_backup';
  static const _formatVersion = 1;
  static const _maxArchiveEntries = 10000;
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

  Future<void> _cleanupStaging(Directory staging) async {
    try {
      if (!await staging.exists()) return;
      final root = await Directory(
        await getDatabasesPath(),
      ).resolveSymbolicLinks();
      final target = await staging.resolveSymbolicLinks();
      if (!path.isWithin(root, target)) {
        throw StateError('Güvensiz geçici yedek yolu.');
      }
      await staging.delete(recursive: true);
    } on FileSystemException {
      // Verified data/safety backups remain usable if a temp file is locked.
    }
  }

  Future<File> createBackup({bool omitMissingPhotos = false}) async {
    return DatabaseService.instance.withMaintenance(
      (access) => _createBackup(access, omitMissingPhotos: omitMissingPhotos),
    );
  }

  Future<File> _createBackup(
    DatabaseMaintenance access, {
    bool omitMissingPhotos = false,
  }) async {
    final staging = await _stagingDirectory('create');
    File? target;
    await access.close();
    try {
      final source = File(await _databasePath());
      if (!await source.exists()) {
        await access.open();
        await access.close();
      }
      final snapshot = await source.copy(
        path.join(staging.path, 'barberbook.db'),
      );
      final collection = await _managedPhotoEntries(snapshot);
      if (collection.missingPaths.isNotEmpty) {
        if (!omitMissingPhotos) {
          throw MissingBackupPhotosException(collection.missingPaths.length);
        }
        await _removeMissingPhotoReferences(snapshot, collection.missingPaths);
      }
      final databaseBytes = await snapshot.readAsBytes();
      final photos = collection.photos;
      final manifestBytes = utf8.encode(
        jsonEncode({
          'format': _format,
          'formatVersion': _formatVersion,
          'database': _databaseArchivePath,
          'photos': [for (final photo in photos) photo.toJson()],
        }),
      );
      _checkArchiveLimits(
        photos.length + 2,
        databaseBytes.length +
            manifestBytes.length +
            photos.fold<int>(0, (sum, photo) => sum + photo.bytes.length),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            _databaseArchivePath,
            databaseBytes.length,
            databaseBytes,
          ),
        );
      for (final photo in photos) {
        archive.addFile(
          ArchiveFile(photo.archivePath, photo.bytes.length, photo.bytes),
        );
      }
      archive.addFile(
        ArchiveFile(_manifestPath, manifestBytes.length, manifestBytes),
      );
      final directory = await _backupDirectory();
      final baseName = 'barberbook_${_stamp()}';
      var candidate = File(path.join(directory.path, '$baseName.zip'));
      var duplicateIndex = 1;
      while (await candidate.exists()) {
        candidate = File(
          path.join(directory.path, '${baseName}_${duplicateIndex++}.zip'),
        );
      }
      target = candidate;
      await candidate.writeAsBytes(
        ZipEncoder().encodeBytes(archive),
        flush: true,
      );
      // A successful backup must obey exactly the same rules as an import.
      await validateBackup(candidate);
      return candidate;
    } catch (_) {
      if (target != null && await target.exists()) await target.delete();
      rethrow;
    } finally {
      await _cleanupStaging(staging);
      await access.open();
    }
  }

  void _checkArchiveLimits(int count, int size) {
    if (count > _maxArchiveEntries) {
      throw StateError(
        'Yedek arşivi çok fazla dosya içeriyor (en fazla ${_maxArchiveEntries - 2} fotoğraf).',
      );
    }
    if (size > _maxArchiveBytes) {
      throw StateError(
        'Yedek arşivi çok büyük (açılmış içerik en fazla 200 MB).',
      );
    }
  }

  Future<void> _removeMissingPhotoReferences(
    File database,
    List<String> missing,
  ) async {
    final candidate = await openDatabase(database.path, singleInstance: false);
    try {
      await candidate.transaction((txn) async {
        for (final photoPath in missing) {
          await txn.update(
            'customers',
            {'photoPath': null},
            where: 'photoPath = ?',
            whereArgs: [photoPath],
          );
          await txn.delete(
            'customer_photos',
            where: 'photoPath = ?',
            whereArgs: [photoPath],
          );
        }
      });
    } finally {
      await candidate.close();
    }
  }

  Future<_BackupPhotoCollection> _managedPhotoEntries(File database) async {
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
      final missingPaths = <String>[];
      var totalSize = await database.length();
      for (final row in rows) {
        final databasePath = row['photoPath'] as String?;
        if (databasePath == null ||
            databasePath.isEmpty ||
            !seenPaths.add(databasePath)) {
          continue;
        }
        final photo = File(databasePath);
        if (!path.isWithin(photosDirectory.path, databasePath) ||
            !await photo.exists()) {
          missingPaths.add(databasePath);
          continue;
        }
        totalSize += await photo.length();
        _checkArchiveLimits(entries.length + 3, totalSize);
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
      return _BackupPhotoCollection(entries, missingPaths);
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
        await _cleanupStaging(staging);
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
      _checkArchiveLimits(archive.files.length, 0);
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
        _checkArchiveLimits(archive.files.length, totalSize);
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
      await _cleanupStaging(staging);
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
    bool omitMissingSafetyPhotos = false,
  }) async {
    await validateBackup(backup);
    await DatabaseService.instance.withMaintenance((access) async {
      await _createBackup(access, omitMissingPhotos: omitMissingSafetyPhotos);
      await access.close();
      final transaction = await RestoreFileTransaction.at(
        await getDatabasesPath(),
      );
      Directory? staging;
      try {
        final contents = await _stageRestoreContents(backup);
        staging = contents.directory;
        await transaction.install(
          database: contents.database,
          photos: contents.photos,
        );
        final db = await access.open();
        final integrity = await db.rawQuery('PRAGMA integrity_check');
        if (integrity.single.values.single != 'ok' ||
            (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw StateError('Geri yüklenen veritabanı doğrulanamadı.');
        }
        await transaction.commit();
        access.markReplaced();
      } catch (error) {
        await access.close();
        try {
          await transaction.recoverInterrupted();
          await access.open();
        } catch (_) {
          throw StateError(
            'Geri yükleme tamamlanamadı. Korunan dosyalar ve güvenlik yedeği saklandı; uygulamayı yeniden açarak kurtarmayı deneyin.',
          );
        }
        rethrow;
      } finally {
        transaction.release();
        if (staging != null) await _cleanupStaging(staging);
      }
    });
    // Native alarm synchronization can safely read the replacement after the gate opens.
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

  Future<({Directory directory, File database, Directory photos})>
  _stageRestoreContents(File backup) async {
    final archive = await _isZip(backup) ? await _readArchive(backup) : null;
    final staging = await _stagingDirectory('restore');
    try {
      final database = File(path.join(staging.path, 'barberbook.db'));
      final photos = Directory(path.join(staging.path, 'photos'));
      await photos.create();
      if (archive == null) {
        await backup.copy(database.path);
      } else {
        await database.writeAsBytes(archive.databaseBytes, flush: true);
        for (final photo in archive.photos) {
          await File(
            path.join(photos.path, path.basename(photo.archivePath)),
          ).writeAsBytes(photo.bytes, flush: true);
        }
      }
      // Validate the actual staged bytes, not only the earlier preview/source.
      await _validateDatabase(database);
      if (archive != null) {
        await _validateArchivePhotoReferences(database, archive.photos);
        await _rewriteRestoredPhotoPaths(
          database,
          await _photosDirectory(),
          archive.photos,
        );
      } else {
        await _clearLegacyPhotoReferences(database);
      }
      return (directory: staging, database: database, photos: photos);
    } catch (_) {
      await _cleanupStaging(staging);
      rethrow;
    }
  }

  Future<void> _clearLegacyPhotoReferences(File file) async {
    final database = await openDatabase(file.path, singleInstance: false);
    try {
      await database.transaction((txn) async {
        final columns = await txn.rawQuery('PRAGMA table_info(customers)');
        if (columns.any((column) => column['name'] == 'photoPath')) {
          await txn.update('customers', {'photoPath': null});
        }
        final tables = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'customer_photos'",
        );
        if (tables.isNotEmpty) await txn.delete('customer_photos');
      });
    } finally {
      await database.close();
    }
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

class MissingBackupPhotosException extends StateError {
  final int count;
  MissingBackupPhotosException(this.count)
    : super(
        '$count fotoğraf dosyası bulunamadı. Mevcut veriler değişmedi; eksik fotoğraf bağlantıları çıkarılarak ayrıca yedek oluşturabilirsiniz.',
      );
}

class _BackupPhotoCollection {
  final List<_PhotoEntry> photos;
  final List<String> missingPaths;
  const _BackupPhotoCollection(this.photos, this.missingPaths);
}
