import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

enum RestoreSwapStep {
  prepared,
  oldFilesMoved,
  newDatabaseInstalled,
  newPhotosInstalled,
}

/// Keeps the previous database/photos until the replacement has opened safely.
/// An uncommitted swap is rolled back before SQLite opens on the next startup.
class RestoreFileTransaction {
  RestoreFileTransaction._(this.root);
  final String root;
  bool _ownsSession = false;
  static final Set<String> _activeRoots = {};
  static const _sidecars = ['-wal', '-shm', '-journal'];
  Directory get _directory => Directory(p.join(root, 'restore_transaction'));
  File get _state => File(p.join(_directory.path, 'state.json'));
  File get _committed => File(p.join(_directory.path, 'committed'));
  File get _installIntent =>
      File(p.join(_directory.path, 'installing_database'));
  File get _oldDatabase => File(p.join(_directory.path, 'old.db'));
  Directory get _oldPhotos => Directory(p.join(_directory.path, 'old_photos'));
  File get _newDatabase => File(p.join(_directory.path, 'new.db'));
  Directory get _newPhotos => Directory(p.join(_directory.path, 'new_photos'));
  File get _database => File(p.join(root, 'barberbook.db'));
  Directory get _photos => Directory(p.join(root, 'photos'));

  static Future<RestoreFileTransaction> at(String databaseDirectory) async {
    final directory = Directory(databaseDirectory);
    await directory.create(recursive: true);
    return RestoreFileTransaction._(await directory.resolveSymbolicLinks());
  }

  static Future<void> recoverBeforeOpening(String databaseDirectory) async {
    final transaction = await at(databaseDirectory);
    if (!_activeRoots.contains(transaction.root)) {
      await transaction.recoverInterrupted();
    }
  }

  Future<void> _removeDirectory(Directory directory) async {
    final absolute = p.normalize(directory.absolute.path);
    if (!p.isWithin(root, absolute)) {
      throw StateError('Güvensiz kurtarma yolu.');
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// The callback is also useful for deterministic interruption/fault tests.
  Future<void> install({
    required File database,
    required Directory photos,
    Future<void> Function(RestoreSwapStep)? afterStep,
  }) async {
    if (p.equals(p.normalize(database.absolute.path), _database.path) ||
        p.equals(p.normalize(photos.absolute.path), _photos.path)) {
      throw StateError('Geri yükleme için ayrı hazırlanmış dosyalar gerekir.');
    }
    if (_activeRoots.contains(root)) {
      throw StateError('Geri yükleme zaten sürüyor.');
    }
    await recoverInterrupted();
    if (await _directory.exists()) {
      throw StateError(
        'Önceki kurtarma dosyaları temizlenemedi; yeni geri yükleme başlatılmadı.',
      );
    }
    _activeRoots.add(root);
    _ownsSession = true;
    await _directory.create(recursive: true);
    if (p.isWithin(root, p.normalize(database.absolute.path))) {
      await database.rename(_newDatabase.path);
    } else {
      await database.copy(_newDatabase.path);
    }
    if (p.isWithin(root, p.normalize(photos.absolute.path))) {
      await photos.rename(_newPhotos.path);
    } else {
      await _newPhotos.create();
      await for (final entry in photos.list(followLinks: false)) {
        if (entry is! File) {
          throw StateError('Fotoğraf yedeğinde geçersiz dosya yapısı.');
        }
        await entry.copy(p.join(_newPhotos.path, p.basename(entry.path)));
      }
    }
    await _state.writeAsString(
      jsonEncode({
        'version': 1,
        'hadDatabase': await _database.exists(),
        'hadPhotos': await _photos.exists(),
      }),
      flush: true,
    );
    await afterStep?.call(RestoreSwapStep.prepared);
    if (await _database.exists()) await _database.rename(_oldDatabase.path);
    final sidecars = Directory(p.join(_directory.path, 'old_sidecars'));
    await sidecars.create();
    for (final suffix in _sidecars) {
      final file = File('${_database.path}$suffix');
      if (await file.exists()) {
        await file.rename(p.join(sidecars.path, p.basename(file.path)));
      }
    }
    if (await _photos.exists()) await _photos.rename(_oldPhotos.path);
    await afterStep?.call(RestoreSwapStep.oldFilesMoved);
    // Persist intent before installing a DB that can create its own WAL/journal.
    await _installIntent.writeAsString('new database', flush: true);
    await _newDatabase.rename(_database.path);
    await afterStep?.call(RestoreSwapStep.newDatabaseInstalled);
    await _newPhotos.rename(_photos.path);
    await afterStep?.call(RestoreSwapStep.newPhotosInstalled);
  }

  /// Call only after SQLite has opened/migrated and checked the replacement.
  Future<void> commit({Future<void> Function(String)? afterRemoved}) async {
    await _committed.writeAsString('committed', flush: true);
    await _tryCleanupCommitted(afterRemoved: afterRemoved);
  }

  Future<void> _tryCleanupCommitted({
    Future<void> Function(String)? afterRemoved,
  }) async {
    try {
      // The commit marker is removed LAST. A crash while deleting old snapshots
      // must never turn an already committed replacement into a rollback.
      await for (final entry in _directory.list(followLinks: false)) {
        if (p.equals(entry.path, _committed.path)) continue;
        if (entry is Directory) {
          await _removeDirectory(entry);
        } else {
          await entry.delete();
        }
        await afterRemoved?.call(p.basename(entry.path));
      }
      await _committed.delete();
      await _directory.delete();
    } on FileSystemException {
      // The marker survives unfinished cleanup; the active new data stays valid.
    }
  }

  Future<void> _tryCleanup() async {
    try {
      await _removeDirectory(_directory);
    } on FileSystemException {
      // The active file group is complete; retry leftover cleanup on startup.
    }
  }

  void release() {
    if (_ownsSession) _activeRoots.remove(root);
    _ownsSession = false;
  }

  Future<void> recoverInterrupted() async {
    if (!await _directory.exists()) return;
    if (await _committed.exists()) {
      await _tryCleanupCommitted();
      return;
    }
    if (!await _state.exists()) {
      if (await _oldDatabase.exists() || await _oldPhotos.exists()) {
        throw StateError(
          'Kurtarma bilgisi eksik; korunan eski dosyalara dokunulmadı.',
        );
      }
      await _tryCleanup();
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await _state.readAsString());
    } catch (_) {
      throw StateError('Kurtarma bilgisi okunamadı; eski dosyalar korunuyor.');
    }
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['hadDatabase'] is! bool ||
        decoded['hadPhotos'] is! bool) {
      throw StateError('Kurtarma bilgisi geçersiz; eski dosyalar korunuyor.');
    }
    // A replacement may have crashed while SQLite was writing its own journal.
    // Remove those sidecars before bringing the previous DB family back.
    if (await _installIntent.exists()) {
      for (final suffix in _sidecars) {
        final file = File('${_database.path}$suffix');
        if (await file.exists()) await file.delete();
      }
      await _installIntent.delete();
    }
    if (await _oldDatabase.exists()) {
      if (await _database.exists()) await _database.delete();
      await _oldDatabase.rename(_database.path);
    } else if (decoded['hadDatabase'] == true && !await _database.exists()) {
      throw StateError(
        'Önceki veritabanı bulunamadı; kurtarma dosyaları korunuyor.',
      );
    } else if (decoded['hadDatabase'] == false && await _database.exists()) {
      await _database.delete();
    }
    for (final suffix in _sidecars) {
      final old = File(
        p.join(_directory.path, 'old_sidecars', 'barberbook.db$suffix'),
      );
      if (await old.exists()) {
        final target = File('${_database.path}$suffix');
        if (await target.exists()) await target.delete();
        await old.rename(target.path);
      }
    }
    if (await _oldPhotos.exists()) {
      await _removeDirectory(_photos);
      await _oldPhotos.rename(_photos.path);
    } else if (decoded['hadPhotos'] == false) {
      await _removeDirectory(_photos);
    }
    await _tryCleanup();
  }
}
