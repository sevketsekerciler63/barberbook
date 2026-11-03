import 'dart:async';
import 'dart:io';
import 'package:berber_randevu/services/backup_file_gateway.dart';
import 'package:berber_randevu/widgets/backup_reminder.dart';
import 'package:berber_randevu/screens/backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Files extends BackupFileGateway {
  late Future<List<BackupFileEntry>> Function() read;
  @override
  Future<List<BackupFileEntry>> list() => read();
}

BackupFileEntry entry(DateTime date) =>
    BackupFileEntry(file: File('local.zip'), modified: date, sizeBytes: 100);

void main() {
  final today = DateTime(2026, 11, 3, 12);
  Widget show(
    _Files files, {
    int revision = 0,
    Future<void> Function()? open,
    DateTime Function()? now,
  }) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          BackupReminder(
            files: files,
            revision: revision,
            now: now ?? () => today,
            onOpen: open ?? () async {},
          ),
        ],
      ),
    ),
  );

  testWidgets('overdue opens once, return reloads and hides recent reminder', (
    tester,
  ) async {
    var filesNow = [entry(DateTime(2026, 10, 20))];
    final files = _Files()..read = () async => filesNow;
    final navigation = Completer<void>();
    var opens = 0;
    await tester.pumpWidget(
      show(
        files,
        open: () {
          opens++;
          return navigation.future;
        },
      ),
    );
    await tester.pump();
    expect(find.text('14 gündür yeni yedek yok'), findsOneWidget);
    await tester.tap(find.text('Yedeklemeyi aç'));
    await tester.tap(find.text('Yedeklemeyi aç'));
    expect(opens, 1);
    filesNow = [entry(today)];
    navigation.complete();
    await tester.pump();
    expect(find.byType(BackupSummary), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read error is visible and menu revision refreshes to missing', (
    tester,
  ) async {
    final files = _Files()
      ..read = () async => throw const FileSystemException('denied');
    await tester.pumpWidget(show(files));
    await tester.pump();
    expect(find.text('Yedek durumu okunamadı'), findsOneWidget);
    expect(find.text('Henüz yerel yedek yok'), findsNothing);
    files.read = () async => [];
    await tester.pumpWidget(show(files, revision: 1));
    await tester.pump();
    expect(find.text('Henüz yerel yedek yok'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'resume supersedes stale read and disposal ignores late failure',
    (tester) async {
      final first = Completer<List<BackupFileEntry>>();
      final last = Completer<List<BackupFileEntry>>();
      var reads = 0;
      final files = _Files()
        ..read = () => switch (++reads) {
          1 => first.future,
          2 => Future.value([entry(today)]),
          _ => last.future,
        };
      await tester.pumpWidget(show(files));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      first.complete([]);
      await tester.pump();
      expect(find.byType(BackupSummary), findsNothing);
      await tester.pumpWidget(show(files, revision: 1));
      await tester.pumpWidget(const SizedBox());
      last.completeError(const FileSystemException('late'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visible screen rechecks calendar threshold hourly', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 2, 23, 30);
    final files = _Files()..read = () async => [entry(DateTime(2026, 10, 27))];
    await tester.pumpWidget(show(files, now: () => now));
    await tester.pump();
    expect(find.byType(BackupSummary), findsNothing);
    now = DateTime(2026, 11, 3, 0, 30);
    await tester.pump(const Duration(hours: 1));
    await tester.pump();
    expect(find.text('7 gündür yeni yedek yok'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reminder is scrollable with large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final files = _Files()..read = () async => [];
    await tester.pumpWidget(show(files));
    await tester.pump();
    expect(find.text('Yedeklemeyi aç'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'backup management shows latest file date without claiming shared copy',
    (tester) async {
      final files = _Files()
        ..read = () async => [entry(DateTime(2026, 10, 20, 9, 15))];
      await tester.pumpWidget(MaterialApp(home: BackupScreen(files: files)));
      await tester.pump();
      expect(find.text('20.10.2026 09:15'), findsOneWidget);
      expect(
        find.text('Yedeğinizin bir kopyasını cihaz dışına da kaydedin.'),
        findsOneWidget,
      );
      expect(find.text('Yedek 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
