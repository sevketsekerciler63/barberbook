import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_service.dart';
import 'notification_service.dart';
import 'whatsapp_service.dart';

/// Platform work is injectable so failed startup paths can be exercised without
/// accessing real user data or initializing Android alarms in widget tests.
class StartupGateway {
  const StartupGateway();

  Future<void> preparePlatform() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    await initializeDateFormatting('tr_TR', null);
  }

  Future<void> openData() async {
    // Opening uses the existing restore recovery gate. Never bypass an error
    // here by deleting data or opening a replacement empty database.
    await DatabaseService.instance.database;
  }

  Future<void> prepareReminders() =>
      WhatsAppService.instance.prepareReminderHistory();

  Future<void> initializeAlarms() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Alarm.init();
      await NotificationService.instance.initialize();
    }
  }

  /// The portfolio app needs no license. Private main supplies its own check.
  Future<bool> resolveAccess() async => true;
}

enum StartupStage { platform, data, reminders, alarms, access }

extension StartupStageLabel on StartupStage {
  String get label => switch (this) {
    StartupStage.platform => 'Uygulama hazırlanıyor',
    StartupStage.data => 'Kayıtlar açılıyor',
    StartupStage.reminders => 'Hatırlatmalar hazırlanıyor',
    StartupStage.alarms => 'Bildirimler hazırlanıyor',
    StartupStage.access => 'Erişim kontrol ediliyor',
  };
}

/// Retry starts at the failed stage; successful stages are not repeated.
/// In particular, native callbacks cannot start before data/history are ready.
class StartupSequence {
  final StartupGateway gateway;
  int _nextStage = 0;
  bool _allowed = false;
  Future<bool>? _running;

  StartupSequence(this.gateway);

  Future<bool> run({required void Function(StartupStage) onStage}) {
    final pending = _running;
    if (pending != null) return pending;
    final completion = Completer<bool>();
    _running = completion.future;
    _run(onStage).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<bool> _run(void Function(StartupStage) onStage) async {
    try {
      while (_nextStage < StartupStage.values.length) {
        final stage = StartupStage.values[_nextStage];
        onStage(stage);
        switch (stage) {
          case StartupStage.platform:
            await gateway.preparePlatform();
          case StartupStage.data:
            await gateway.openData();
          case StartupStage.reminders:
            await gateway.prepareReminders();
          case StartupStage.alarms:
            await gateway.initializeAlarms();
          case StartupStage.access:
            _allowed = await gateway.resolveAccess();
        }
        _nextStage++;
      }
      return _allowed;
    } finally {
      _running = null;
    }
  }
}
