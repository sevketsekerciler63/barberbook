import 'dart:io';
import 'package:berber_randevu/services/backup_file_gateway.dart';
import 'package:berber_randevu/services/backup_recency.dart';
import 'package:flutter_test/flutter_test.dart';

BackupFileEntry entry(DateTime time, {int size = 100}) =>
    BackupFileEntry(file: File('backup.zip'), modified: time, sizeBytes: size);

void main() {
  test('no files requires a first backup', () {
    final status = BackupRecency.fromEntries([], now: DateTime(2026, 11, 3));
    expect(status.kind, BackupRecencyKind.missing);
    expect(status.needsAttention, isTrue);
  });

  test('seven calendar days triggers even before 168 elapsed hours', () {
    final files = [entry(DateTime(2026, 10, 27, 23, 59))];
    final recent = BackupRecency.fromEntries(files, now: DateTime(2026, 11, 2));
    final due = BackupRecency.fromEntries(files, now: DateTime(2026, 11, 3));
    expect(recent.kind, BackupRecencyKind.recent);
    expect(recent.needsAttention, isFalse);
    expect(due.kind, BackupRecencyKind.overdue);
    expect(due.ageDays, 7);
  });

  test(
    'year boundary uses calendar dates and newest metadata, not list order',
    () {
      final newest = DateTime(2026, 12, 31, 23);
      final status = BackupRecency.fromEntries([
        entry(DateTime(2026, 12, 1)),
        entry(newest),
        entry(DateTime(2026, 12, 20)),
      ], now: DateTime(2027, 1, 1));
      expect(status.latest, newest);
      expect(status.ageDays, 1);
    },
  );

  test(
    'zero length and unreadable files cannot suppress an overdue backup',
    () {
      final status = BackupRecency.fromEntries([
        entry(DateTime(2026, 11, 3), size: 0),
        BackupFileEntry(file: File('vanished.zip')),
        entry(DateTime(2026, 10, 1)),
      ], now: DateTime(2026, 11, 3));
      expect(status.kind, BackupRecencyKind.overdue);
      expect(status.ageDays, 33);
    },
  );

  test('unreadable or empty files are unknown, not missing or recent', () {
    final status = BackupRecency.fromEntries([
      BackupFileEntry(file: File('unreadable.zip')),
      entry(DateTime(2026, 11, 3), size: 0),
    ], now: DateTime(2026, 11, 3));
    expect(status.kind, BackupRecencyKind.unavailable);
    expect(status.latest, isNull);
  });

  test(
    'future dated files request a clock check instead of hiding reminder',
    () {
      final status = BackupRecency.fromEntries([
        entry(DateTime(2027, 1, 1)),
      ], now: DateTime(2026, 11, 3));
      expect(status.kind, BackupRecencyKind.futureDate);
      expect(status.needsAttention, isTrue);
    },
  );
}
