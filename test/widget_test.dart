import 'dart:async';

import 'package:berber_randevu/services/startup_service.dart';
import 'package:berber_randevu/widgets/startup_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Startup extends StartupGateway {
  final calls = <StartupStage>[];
  final Map<StartupStage, Future<void> Function()> actions = {};
  bool access = true;

  Future<void> _step(StartupStage stage) {
    calls.add(stage);
    return actions[stage]?.call() ?? Future.value();
  }

  @override
  Future<void> preparePlatform() => _step(StartupStage.platform);
  @override
  Future<void> openData() => _step(StartupStage.data);
  @override
  Future<void> prepareReminders() => _step(StartupStage.reminders);
  @override
  Future<void> initializeAlarms() => _step(StartupStage.alarms);
  @override
  Future<bool> resolveAccess() async {
    await _step(StartupStage.access);
    return access;
  }
}

Widget _launch(_Startup gateway) => StartupGate(
  gateway: gateway,
  readyBuilder: (_, allowed) => MaterialApp(
    home: Scaffold(body: Text(allowed ? 'Ready home' : 'License required')),
  ),
);

void main() {
  testWidgets('startup shell appears before pending platform initialization', (
    tester,
  ) async {
    final pending = Completer<void>();
    final gateway = _Startup()
      ..actions[StartupStage.platform] = () => pending.future;
    await tester.pumpWidget(_launch(gateway));
    expect(find.text('BarberBook'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Ready home'), findsNothing);
    expect(gateway.calls, [StartupStage.platform]);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ready home'), findsOneWidget);
    expect(gateway.calls, StartupStage.values);
  });

  testWidgets(
    'data recovery failure blocks home and alarms, retry keeps prior stages',
    (tester) async {
      final gateway = _Startup()
        ..actions[StartupStage.data] = () =>
            throw StateError('private data path');
      await tester.pumpWidget(_launch(gateway));
      await tester.pumpAndSettle();
      expect(find.text('Uygulama hazırlanamadı.'), findsOneWidget);
      expect(find.text('Kayıtlar açılıyor'), findsOneWidget);
      expect(find.textContaining('private data path'), findsNothing);
      expect(find.text('Ready home'), findsNothing);
      expect(gateway.calls, [StartupStage.platform, StartupStage.data]);

      final pending = Completer<void>();
      gateway.actions[StartupStage.data] = () => pending.future;
      await tester.tap(find.text('Yeniden dene'));
      await tester.tap(find.text('Yeniden dene'));
      expect(gateway.calls.where((s) => s == StartupStage.data), hasLength(2));
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Ready home'), findsOneWidget);
      expect(gateway.calls, [
        StartupStage.platform,
        StartupStage.data,
        StartupStage.data,
        StartupStage.reminders,
        StartupStage.alarms,
        StartupStage.access,
      ]);
    },
  );

  testWidgets('failed reminder migration cannot start alarm callbacks', (
    tester,
  ) async {
    final gateway = _Startup()
      ..actions[StartupStage.reminders] = () async =>
          throw StateError('migration');
    await tester.pumpWidget(_launch(gateway));
    await tester.pumpAndSettle();
    expect(find.text('Hatırlatmalar hazırlanıyor'), findsOneWidget);
    expect(gateway.calls, [
      StartupStage.platform,
      StartupStage.data,
      StartupStage.reminders,
    ]);
    gateway.actions.remove(StartupStage.reminders);
    await tester.tap(find.text('Yeniden dene'));
    await tester.pumpAndSettle();
    expect(find.text('Ready home'), findsOneWidget);
    expect(gateway.calls.where((s) => s == StartupStage.data), hasLength(1));
    expect(gateway.calls.where((s) => s == StartupStage.alarms), hasLength(1));
  });

  testWidgets('alarm setup failure is recoverable and access stays uncalled', (
    tester,
  ) async {
    final gateway = _Startup()
      ..actions[StartupStage.alarms] = () async =>
          throw StateError('native setup');
    await tester.pumpWidget(_launch(gateway));
    await tester.pumpAndSettle();
    expect(find.text('Bildirimler hazırlanıyor'), findsOneWidget);
    expect(gateway.calls.contains(StartupStage.access), isFalse);
    gateway.actions.remove(StartupStage.alarms);
    await tester.tap(find.text('Yeniden dene'));
    await tester.pumpAndSettle();
    expect(find.text('Ready home'), findsOneWidget);
    expect(
      gateway.calls.where((s) => s == StartupStage.reminders),
      hasLength(1),
    );
  });

  testWidgets(
    'access exception retries access only and denied access routes away from home',
    (tester) async {
      final gateway = _Startup()
        ..access = false
        ..actions[StartupStage.access] = () async =>
            throw StateError('license read');
      await tester.pumpWidget(_launch(gateway));
      await tester.pumpAndSettle();
      expect(find.text('Uygulama hazırlanamadı.'), findsOneWidget);
      expect(find.text('License required'), findsNothing);
      gateway.actions.remove(StartupStage.access);
      await tester.tap(find.text('Yeniden dene'));
      await tester.pumpAndSettle();
      expect(find.text('License required'), findsOneWidget);
      expect(find.text('Ready home'), findsNothing);
      expect(
        gateway.calls.where((s) => s == StartupStage.alarms),
        hasLength(1),
      );
      expect(
        gateway.calls.where((s) => s == StartupStage.access),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'late startup error after disposal never updates disposed state',
    (tester) async {
      final pending = Completer<void>();
      final gateway = _Startup()
        ..actions[StartupStage.data] = () => pending.future;
      await tester.pumpWidget(_launch(gateway));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.completeError(StateError('late failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(gateway.calls.contains(StartupStage.alarms), isFalse);
    },
  );

  testWidgets('retry screen fits a narrow viewport with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = _Startup()
      ..actions[StartupStage.platform] = () => throw StateError('platform');
    await tester.pumpWidget(_launch(gateway));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Yeniden dene'));
    gateway.actions.remove(StartupStage.platform);
    await tester.tap(find.text('Yeniden dene'));
    await tester.pumpAndSettle();
    expect(find.text('Ready home'), findsOneWidget);
  });

  test('concurrent startup calls share a single operation', () async {
    final pending = Completer<void>();
    final gateway = _Startup()
      ..actions[StartupStage.data] = () => pending.future;
    final sequence = StartupSequence(gateway);
    final first = sequence.run(onStage: (_) {});
    final second = sequence.run(onStage: (_) {});
    expect(identical(first, second), isTrue);
    pending.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(gateway.calls, StartupStage.values);
  });
}
