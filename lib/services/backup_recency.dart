import 'backup_file_gateway.dart';

enum BackupRecencyKind { missing, recent, overdue, unavailable, futureDate }

/// A reminder based on local file metadata, not a claim of archive integrity
/// or successful off-device sharing. Calendar days avoid DST rounding errors.
class BackupRecency {
  final BackupRecencyKind kind;
  final DateTime? latest;
  final int? ageDays;

  const BackupRecency._(this.kind, {this.latest, this.ageDays});
  const BackupRecency.unavailable() : this._(BackupRecencyKind.unavailable);

  bool get needsAttention => kind != BackupRecencyKind.recent;

  factory BackupRecency.fromEntries(
    List<BackupFileEntry> entries, {
    required DateTime now,
  }) {
    if (entries.isEmpty) {
      return const BackupRecency._(BackupRecencyKind.missing);
    }
    DateTime? latest;
    for (final entry in entries) {
      if (!entry.isAvailable || entry.sizeBytes! <= 0) continue;
      final date = entry.modified!.toLocal();
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    if (latest == null) return const BackupRecency.unavailable();
    final today = now.toLocal();
    final days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(latest.year, latest.month, latest.day)).inDays;
    return BackupRecency._(
      days < 0
          ? BackupRecencyKind.futureDate
          : days >= 7
          ? BackupRecencyKind.overdue
          : BackupRecencyKind.recent,
      latest: latest,
      ageDays: days,
    );
  }

  String get title => switch (kind) {
    BackupRecencyKind.missing => 'Henüz yerel yedek yok',
    BackupRecencyKind.recent => 'Son yerel yedek dosyası',
    BackupRecencyKind.overdue => '$ageDays gündür yeni yedek yok',
    BackupRecencyKind.unavailable => 'Yedek durumu okunamadı',
    BackupRecencyKind.futureDate => 'Yedek dosyasının tarihi ileride',
  };
}
