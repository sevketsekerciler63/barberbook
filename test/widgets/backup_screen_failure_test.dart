import 'dart:async';
import 'dart:io';
import 'package:berber_randevu/screens/backup_screen.dart';
import 'package:berber_randevu/services/backup_file_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Files extends BackupFileGateway {
  Future<List<BackupFileEntry>> Function()? onList;
  Future<File?> Function()? onPick;
  Future<void> Function(File)? onShare;
  int picks = 0;
  int shares = 0;
  @override
  Future<List<BackupFileEntry>> list() async =>
      onList == null ? [] : await onList!();
  @override
  Future<File?> pick() async {
    picks++;
    return onPick == null ? null : await onPick!();
  }

  @override
  Future<void> share(File file) async {
    shares++;
    await onShare?.call(file);
  }
}

void main() {
  const pickerTooltip = 'ZIP veya eski DB yedeğini içe aktar';
  final entry = BackupFileEntry(
    file: File('previously-listed-backup.zip'),
    modified: DateTime(2026, 11, 3, 10),
    sizeBytes: 1024,
  );
  Future<void> show(WidgetTester tester, _Files files) async {
    await tester.pumpWidget(MaterialApp(home: BackupScreen(files: files)));
    await tester.pump();
  }

  testWidgets(
    'list failure remains visible and retry recovers without claiming empty backups',
    (tester) async {
      var calls = 0;
      final files = _Files()
        ..onList = () async {
          if (calls++ == 0) {
            throw const FileSystemException('directory unavailable');
          }
          return [];
        };
      await show(tester, files);
      expect(find.text('Yedekler yüklenemedi.'), findsOneWidget);
      expect(find.text('Henüz yedek oluşturulmadı.'), findsNothing);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pump();
      expect(find.text('Henüz yedek oluşturulmadı.'), findsOneWidget);
      expect(find.text('Yedekler yüklenemedi.'), findsNothing);
      expect(calls, 2);
    },
  );

  testWidgets(
    'native picker failure is handled and a later attempt is usable',
    (tester) async {
      final files = _Files()
        ..onPick = () async =>
            throw PlatformException(code: 'picker_unavailable');
      await show(tester, files);
      await tester.tap(find.byTooltip(pickerTooltip));
      await tester.pump();
      expect(
        find.text('Dosya seçimi açılamadı. Yeniden deneyin.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      files.onPick = () async => null;
      await tester.tap(find.byTooltip(pickerTooltip));
      await tester.pump();
      expect(files.picks, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'pending picker blocks duplicate dialogs and cancellation unlocks navigation',
    (tester) async {
      final pending = Completer<File?>();
      final files = _Files()..onPick = () => pending.future;
      await show(tester, files);
      // Tap twice before rebuilding: the method guard must also reject duplicates.
      await tester.tap(find.byTooltip(pickerTooltip));
      await tester.tap(find.byTooltip(pickerTooltip));
      await tester.pump();
      expect(files.picks, 1);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      pending.complete(null);
      await tester.pump();
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'late picker result after disposal never starts restore or updates disposed state',
    (tester) async {
      final pending = Completer<File?>();
      final files = _Files()..onPick = () => pending.future;
      await show(tester, files);
      await tester.tap(find.byTooltip(pickerTooltip));
      await tester.pumpWidget(const SizedBox());
      pending.complete(File('late-result.zip'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Yedeği geri yükle'), findsNothing);
    },
  );

  testWidgets('share failure keeps backup visible and allows retry', (
    tester,
  ) async {
    final files = _Files();
    files.onList = () async => [entry];
    files.onShare = (_) async =>
        throw const FileSystemException('file disappeared');
    await show(tester, files);
    // No synchronous file I/O occurs while building this saved metadata snapshot.
    expect(find.textContaining('1.0 KB'), findsOneWidget);
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pump();
    expect(
      find.text('Yedek paylaşılamadı. Dosyayı kontrol edip tekrar deneyin.'),
      findsOneWidget,
    );
    expect(find.text('Yedek 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    files.onShare = (_) async {};
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pump();
    expect(files.shares, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'pending share rejects duplicates and late completion after disposal is safe',
    (tester) async {
      final pending = Completer<void>();
      final files = _Files();
      files.onList = () async => [entry];
      files.onShare = (_) => pending.future;
      await show(tester, files);
      await tester.tap(find.byTooltip('Paylaş'));
      await tester.tap(find.byTooltip('Paylaş'));
      await tester.pump();
      expect(files.shares, 1);
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable metadata disables file actions until refresh succeeds',
    (tester) async {
      final files = _Files()
        ..onList = () async => [BackupFileEntry(file: entry.file)];
      await show(tester, files);
      expect(
        find.text('Dosya bilgileri okunamadı. Listeyi yenileyin.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.share_outlined),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Geri yükle'))
            .onPressed,
        isNull,
      );
      files.onList = () async => [entry];
      await tester.tap(find.byTooltip('Yedek listesini yenile'));
      await tester.pump();
      expect(find.textContaining('1.0 KB'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.share_outlined),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
