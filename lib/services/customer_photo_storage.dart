import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class CustomerPhotoStorage {
  CustomerPhotoStorage._();

  static Future<String> importImage(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Seçilen fotoğraf bulunamadı.', sourcePath);
    }

    final photosDirectory = Directory(
      path.join(await getDatabasesPath(), 'photos'),
    );
    await photosDirectory.create(recursive: true);

    final extension = path.extension(sourcePath).toLowerCase();
    final fileName =
        'customer_${DateTime.now().microsecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}';
    final destination = path.join(photosDirectory.path, fileName);
    await source.copy(destination);
    return destination;
  }

  static Future<void> deleteManagedPhoto(String? photoPath) async {
    if (photoPath == null || photoPath.isEmpty) return;

    final photosDirectory = Directory(
      path.join(await getDatabasesPath(), 'photos'),
    );
    final managedPrefix = '${photosDirectory.path}${Platform.pathSeparator}';
    if (!photoPath.startsWith(managedPrefix)) return;

    final photo = File(photoPath);
    if (await photo.exists()) {
      await photo.delete();
    }
  }
}
