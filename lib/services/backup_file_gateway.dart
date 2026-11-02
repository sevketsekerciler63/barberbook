import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'backup_service.dart';

/// File metadata is captured before rendering; a disappearing file cannot make
/// the widget tree throw synchronously while building a row.
class BackupFileEntry {
  final File file;
  final DateTime? modified;
  final int? sizeBytes;

  const BackupFileEntry({required this.file, this.modified, this.sizeBytes});

  bool get isAvailable => modified != null && sizeBytes != null;

  static Future<BackupFileEntry> read(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.file) {
        return BackupFileEntry(
          file: file,
          modified: stat.modified,
          sizeBytes: stat.size,
        );
      }
    } on FileSystemException {
      // Keep an inaccessible entry visible with disabled actions and refresh.
    }
    return BackupFileEntry(file: file);
  }
}

/// Native file dialogs and filesystem access used by the backup screen.
class BackupFileGateway {
  const BackupFileGateway();

  Future<List<BackupFileEntry>> list() async {
    final files = await BackupService.instance.listBackups();
    return Future.wait(files.map(BackupFileEntry.read));
  }

  Future<File?> pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'db'],
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  Future<void> share(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: file.path.endsWith('.zip')
                ? 'application/zip'
                : 'application/x-sqlite3',
          ),
        ],
        subject: 'BarberBook yedeği',
        text: 'BarberBook veri ve müşteri fotoğrafları yedeği',
      ),
    );
  }
}
