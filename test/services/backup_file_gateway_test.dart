import 'dart:io';
import 'package:berber_randevu/services/backup_file_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'metadata snapshot survives file removal and a fresh inspection reports unavailable',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'backup_metadata_',
      );
      try {
        final file = await File(
          '${directory.path}/test.zip',
        ).writeAsBytes([1, 2, 3]);
        final entry = await BackupFileEntry.read(file);
        expect(entry.isAvailable, isTrue);
        expect(entry.sizeBytes, 3);
        expect(entry.modified, isNotNull);
        await file.delete();
        expect(entry.sizeBytes, 3);
        expect((await BackupFileEntry.read(file)).isAvailable, isFalse);
        expect(
          (await BackupFileEntry.read(File(directory.path))).isAvailable,
          isFalse,
        );
      } finally {
        final resolved = await directory.resolveSymbolicLinks();
        final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
        expect(p.isWithin(tempRoot, resolved), isTrue);
        expect(p.basename(resolved), startsWith('backup_metadata_'));
        await Directory(resolved).delete(recursive: true);
      }
    },
  );
}
