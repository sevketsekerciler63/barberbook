import 'dart:async';
import 'restore_file_transaction.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../services/customer_photo_storage.dart';
import '../models/customer.dart';
import '../models/customer_photo.dart';
import '../models/appointment.dart';
import '../models/barber_service.dart';
import '../models/hairstyle_template.dart';
import '../models/working_schedule.dart';
import '../models/payment.dart';
import '../models/payment_transaction.dart';
import '../models/cash_report.dart';
import '../models/receivable.dart';
import '../models/payment_account.dart';

class DatabaseService {
  static const schemaVersion = 13;
  static Database? _database;
  Future<Database>? _opening;
  Future<void>? _maintenance;
  int _dataRevision = 0;
  int get dataRevision => _dataRevision;
  static final DatabaseService instance = DatabaseService._init();

  DatabaseService._init();

  Future<Database> get database async {
    while (true) {
      final maintenance = _maintenance;
      if (maintenance != null) {
        await maintenance;
        continue;
      }
      final db = await _openShared();
      if (_maintenance == null && db.isOpen) return db;
    }
  }

  Future<Database> _openShared() async {
    if (_database?.isOpen == true) return _database!;
    _database = null;
    final opening = _opening ??= _initDB('barberbook.db');
    try {
      final db = await opening;
      _database = db;
      return db;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<void> _closeShared() async {
    final opening = _opening;
    if (opening != null) await opening;
    await _database?.close();
    _database = null;
  }

  Future<void> closeDatabase() async {
    while (_maintenance != null) {
      await _maintenance;
    }
    await _closeShared();
  }

  /// Blocks new connections while a closed DB snapshot or file swap is in use.
  Future<T> withMaintenance<T>(
    Future<T> Function(DatabaseMaintenance) action,
  ) async {
    final previous = _maintenance;
    final done = Completer<void>();
    _maintenance = done.future;
    final access = DatabaseMaintenance._(
      _openShared,
      _closeShared,
      () => _dataRevision++,
    );
    try {
      if (previous != null) await previous;
      await _closeShared();
      await RestoreFileTransaction.recoverBeforeOpening(
        await getDatabasesPath(),
      );
      return await action(access);
    } finally {
      access._active = false;
      if (identical(_maintenance, done.future)) _maintenance = null;
      done.complete();
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    await RestoreFileTransaction.recoverBeforeOpening(dbPath);
    final path = join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    // await _cleanupOldData(db); // Geçmiş istatistikleri ve toplam geliş sayısını korumak için silme işlemi iptal edildi.
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        favoriteHairstyle TEXT,
        photoPath TEXT,
        totalAppointments INTEGER DEFAULT 0,
        lastAppointmentDate TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE appointments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER,
        customerName TEXT NOT NULL,
        appointmentDate TEXT NOT NULL,
        appointmentTime TEXT NOT NULL,
        hairstyleId TEXT,
        hairstyleName TEXT,
        serviceId INTEGER,
        serviceName TEXT,
        durationMinutes INTEGER NOT NULL DEFAULT 30,
        priceCents INTEGER,
        notes TEXT,
        isCompleted INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'planned',
        createdAt TEXT NOT NULL,
        FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE SET NULL
      )
    ''');

    await _createServicesTable(db);
    await _seedDefaultServices(db);
    await _createScheduleTables(db);
    await _createPaymentsTable(db);
    await _createPaymentTransactionsTable(db);
    await _createCustomerPhotosTable(db);
    await _createHairstyleTemplatesTable(db);
    await _createShopSettingsTable(db);
  }

  Future<void> _createScheduleTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS working_hours (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        weekday INTEGER NOT NULL,
        startMinute INTEGER NOT NULL,
        endMinute INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_working_hours_weekday ON working_hours(weekday, startMinute)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS closed_time_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startAt TEXT NOT NULL,
        endAt TEXT NOT NULL,
        reason TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_closed_time_blocks_range ON closed_time_blocks(startAt, endAt)',
    );
  }

  Future<void> _createShopSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shop_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        appointmentCapacity INTEGER NOT NULL DEFAULT 1
          CHECK (appointmentCapacity >= 1),
        paymentEnabled INTEGER NOT NULL DEFAULT 1
          CHECK (paymentEnabled IN (0, 1))
      )
    ''');
    await db.insert('shop_settings', {
      'id': 1,
      'appointmentCapacity': 1,
      'paymentEnabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _createServicesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        durationMinutes INTEGER NOT NULL,
        priceCents INTEGER,
        isActive INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> _createPaymentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        appointmentId INTEGER NOT NULL UNIQUE,
        amountCents INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'unknown',
        method TEXT NOT NULL DEFAULT 'other',
        discountCents INTEGER NOT NULL DEFAULT 0,
        tipCents INTEGER NOT NULL DEFAULT 0,
        paidAt TEXT,
        note TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (appointmentId) REFERENCES appointments(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_status_paid_at ON payments(status, paidAt)',
    );
  }

  Future<void> _createCustomerPhotosTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER NOT NULL,
        photoPath TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'reference',
        source TEXT NOT NULL DEFAULT 'gallery',
        createdAt TEXT NOT NULL,
        FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_photos_customer_created '
      'ON customer_photos(customerId, createdAt DESC, id DESC)',
    );
  }

  Future<void> _createHairstyleTemplatesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hairstyle_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_hairstyle_templates_name '
      'ON hairstyle_templates(name COLLATE NOCASE)',
    );
  }

  Future<void> _createPaymentTransactionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        appointmentId INTEGER NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('collection', 'refund', 'adjustment')),
        amountCents INTEGER NOT NULL CHECK (amountCents > 0),
        tipCents INTEGER NOT NULL DEFAULT 0 CHECK (tipCents >= 0 AND tipCents <= amountCents),
        operationId TEXT,
        reversesTransactionId INTEGER REFERENCES payment_transactions(id) ON DELETE RESTRICT,
        method TEXT NOT NULL,
        occurredAt TEXT NOT NULL,
        note TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (appointmentId) REFERENCES appointments(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_transactions_appointment_time '
      'ON payment_transactions(appointmentId, occurredAt, id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payment_transactions_time '
      'ON payment_transactions(occurredAt, id)',
    );
    await _ensureCorrectionColumns(db);
  }

  Future<void> _ensureCorrectionColumns(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(payment_transactions)',
    );
    if (!columns.any((c) => c['name'] == 'tipCents')) {
      await db.execute(
        'ALTER TABLE payment_transactions ADD COLUMN tipCents INTEGER NOT NULL DEFAULT 0 CHECK (tipCents >= 0 AND tipCents <= amountCents)',
      );
    }
    if (!columns.any((c) => c['name'] == 'operationId')) {
      await db.execute(
        'ALTER TABLE payment_transactions ADD COLUMN operationId TEXT',
      );
    }
    if (!columns.any((c) => c['name'] == 'reversesTransactionId')) {
      await db.execute(
        'ALTER TABLE payment_transactions ADD COLUMN reversesTransactionId INTEGER REFERENCES payment_transactions(id) ON DELETE RESTRICT',
      );
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_operation ON payment_transactions(operationId)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_reversal ON payment_transactions(reversesTransactionId)',
    );
  }

  Future<void> _seedDefaultServices(Database db) async {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM services'),
        ) ??
        0;
    if (count > 0) return;

    for (final service in [
      BarberService(name: 'Saç Kesimi', durationMinutes: 30),
      BarberService(name: 'Sakal Tıraşı', durationMinutes: 20),
      BarberService(name: 'Saç + Sakal', durationMinutes: 45),
    ]) {
      await db.insert('services', service.toMap());
    }
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE appointments ADD COLUMN status TEXT NOT NULL DEFAULT 'planned'",
      );
      await db.execute(
        "UPDATE appointments SET status = 'completed' WHERE isCompleted = 1",
      );
    }

    if (oldVersion < 3) {
      // Keep the legacy flag synchronized while status becomes the source of truth.
      await db.execute('''
        UPDATE appointments
        SET status = CASE
          WHEN status = 'completed' OR isCompleted = 1 THEN 'completed'
          WHEN status IN ('cancelled', 'no_show') THEN status
          ELSE 'planned'
        END
      ''');
      await db.execute('''
        UPDATE appointments
        SET isCompleted = CASE WHEN status = 'completed' THEN 1 ELSE 0 END
      ''');
    }

    if (oldVersion < 4) {
      await _createServicesTable(db);
      await db.execute('ALTER TABLE appointments ADD COLUMN serviceId INTEGER');
      await db.execute('ALTER TABLE appointments ADD COLUMN serviceName TEXT');
      await db.execute(
        'ALTER TABLE appointments ADD COLUMN durationMinutes INTEGER NOT NULL DEFAULT 30',
      );
      await db.execute(
        'ALTER TABLE appointments ADD COLUMN priceCents INTEGER',
      );
      await _seedDefaultServices(db);
    }

    if (oldVersion < 5) {
      await _createScheduleTables(db);
    }
    if (oldVersion < 6) {
      await _createPaymentsTable(db);
    }
    if (oldVersion < 7) {
      await _createPaymentTransactionsTable(db);
    }
    if (oldVersion < 8) {
      final customerColumns = await db.rawQuery('PRAGMA table_info(customers)');
      final hasPhotoPath = customerColumns.any(
        (column) => column['name'] == 'photoPath',
      );
      if (!hasPhotoPath) {
        await db.execute('ALTER TABLE customers ADD COLUMN photoPath TEXT');
      }
    }
    if (oldVersion < 9) {
      await _createCustomerPhotosTable(db);
      await db.execute('''
        INSERT INTO customer_photos (customerId, photoPath, type, source, createdAt)
        SELECT id, photoPath, 'reference', 'gallery', createdAt
        FROM customers
        WHERE photoPath IS NOT NULL AND photoPath != ''
      ''');
    }
    if (oldVersion < 10) {
      await _createHairstyleTemplatesTable(db);
    }
    if (oldVersion < 11) {
      await _createShopSettingsTable(db);
    }
    if (oldVersion < 12) {
      final columns = await db.rawQuery('PRAGMA table_info(shop_settings)');
      if (!columns.any((column) => column['name'] == 'paymentEnabled')) {
        await db.execute(
          'ALTER TABLE shop_settings ADD COLUMN paymentEnabled INTEGER NOT NULL DEFAULT 1',
        );
      }
    }
    if (oldVersion < 13) await _ensureCorrectionColumns(db);
  }

  // ==================== PAYMENT CRUD ====================

  Future<int> savePayment(Payment payment) async {
    final db = await database;
    return db.transaction((txn) => _upsertPayment(txn, payment));
  }

  Future<int> _upsertPayment(DatabaseExecutor executor, Payment payment) async {
    final values = payment.toMap()..remove('id');
    final existing = await executor.query(
      'payments',
      columns: ['id', 'createdAt', 'status'],
      where: 'appointmentId = ?',
      whereArgs: [payment.appointmentId],
      limit: 1,
    );
    if (existing.isEmpty) {
      return executor.insert('payments', values);
    }
    if (existing.first['status'] != PaymentStatus.unknown.value) {
      throw StateError(
        'Kayıtlı ödeme değiştirilemez. Veresiye için tahsilat hareketi ekleyin; alınmış tahsilat korunur.',
      );
    }
    values['createdAt'] = existing.first['createdAt'];
    await executor.update(
      'payments',
      values,
      where: 'appointmentId = ?',
      whereArgs: [payment.appointmentId],
    );
    return existing.first['id'] as int;
  }

  Future<void> completeAppointmentWithPayment(
    int appointmentId,
    Payment payment,
  ) async {
    if (payment.appointmentId != appointmentId) {
      throw ArgumentError('Ödeme ile randevu kimliği eşleşmiyor.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final appointment = await txn.query(
        'appointments',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [appointmentId],
        limit: 1,
      );
      if (appointment.isEmpty) {
        throw StateError('Randevu bulunamadı.');
      }
      await _upsertPayment(txn, payment);
      await txn.update(
        'appointments',
        {'status': 'completed', 'isCompleted': 1},
        where: 'id = ?',
        whereArgs: [appointmentId],
      );
    });
  }

  Future<void> completeAppointmentWithoutPayment(int appointmentId) async {
    final db = await database;
    final updated = await db.update(
      'appointments',
      {'status': 'completed', 'isCompleted': 1},
      where: 'id = ?',
      whereArgs: [appointmentId],
    );
    if (updated != 1) throw StateError('Randevu bulunamadı.');
  }

  Future<Payment?> getPaymentForAppointment(int appointmentId) async {
    final db = await database;
    final rows = await db.query(
      'payments',
      where: 'appointmentId = ?',
      whereArgs: [appointmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : Payment.fromMap(rows.first);
  }

  Future<int> recordPaymentTransaction(PaymentTransaction transaction) async {
    final db = await database;
    return db.transaction((txn) async {
      final paymentRows = await txn.query(
        'payments',
        columns: ['amountCents', 'status'],
        where: 'appointmentId = ?',
        whereArgs: [transaction.appointmentId],
        limit: 1,
      );
      if (paymentRows.isEmpty) {
        throw StateError('Randevuya ait ödeme kaydı bulunamadı.');
      }
      if (paymentRows.first['status'] != PaymentStatus.pending.value) {
        throw StateError('Yalnız açık veresiye için tahsilat girilebilir.');
      }
      if (transaction.type != PaymentTransactionType.collection) {
        throw StateError('Bu aşamada yalnız tahsilat hareketi destekleniyor.');
      }
      if (transaction.method == PaymentMethod.credit) {
        throw StateError('Veresiye bir tahsilat yöntemi değildir.');
      }
      if (transaction.reversesTransactionId != null ||
          transaction.tipCents != 0) {
        throw StateError('Tahsilat bu alanlarla kaydedilemez.');
      }

      final account = await _getPaymentAccount(txn, transaction.appointmentId);
      if (transaction.amountCents > account!.outstandingCents) {
        throw StateError('Tahsilat açık veresiye tutarını aşamaz.');
      }
      return txn.insert(
        'payment_transactions',
        transaction.toMap()..remove('id'),
      );
    });
  }

  Future<PaymentAccount?> _getPaymentAccount(
    DatabaseExecutor db,
    int appointmentId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.*, a.customerName, a.serviceName, a.appointmentDate
      FROM payments p JOIN appointments a ON a.id=p.appointmentId
      WHERE p.appointmentId=?''',
      [appointmentId],
    );
    if (rows.isEmpty) return null;
    final movements = await db.query(
      'payment_transactions',
      where: 'appointmentId=?',
      whereArgs: [appointmentId],
      orderBy: 'occurredAt, id',
    );
    return _accountFromRows(rows.single, movements);
  }

  PaymentAccount _accountFromRows(
    Map<String, Object?> row,
    List<Map<String, Object?>> movements,
  ) => PaymentAccount(
    payment: Payment.fromMap(row),
    customerName: row['customerName'] as String,
    serviceName: row['serviceName'] as String?,
    appointmentDate: DateTime.parse(row['appointmentDate'] as String),
    transactions: movements.map(PaymentTransaction.fromMap),
  );

  Future<PaymentAccount?> getPaymentAccount(int appointmentId) async {
    final db = await database;
    return db.transaction((txn) => _getPaymentAccount(txn, appointmentId));
  }

  Future<List<PaymentAccount>> getPaymentAccounts({String query = ''}) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''SELECT p.*, a.customerName, a.serviceName, a.appointmentDate
        FROM payments p JOIN appointments a ON a.id=p.appointmentId
        ORDER BY a.appointmentDate DESC, p.id DESC''',
      );
      final movements = await txn.query(
        'payment_transactions',
        orderBy: 'occurredAt, id',
      );
      final grouped = <int, List<Map<String, Object?>>>{};
      for (final m in movements) {
        (grouped[m['appointmentId'] as int] ??= []).add(m);
      }
      final search = _normalizeTurkish(query.trim());
      return rows
          .where(
            (r) =>
                search.isEmpty ||
                _normalizeTurkish(
                  r['customerName'] as String,
                ).contains(search) ||
                '${r['appointmentId']}' == search,
          )
          .map((r) => _accountFromRows(r, grouped[r['appointmentId']] ?? []))
          .toList();
    });
  }

  /// Refunds cash or writes off unpaid debt without rewriting the original row.
  Future<int> recordPaymentCorrection(PaymentTransaction correction) async {
    final key = correction.operationId;
    final note = correction.note?.trim() ?? '';
    if (key == null ||
        key.trim().isEmpty ||
        key.length > 120 ||
        note.isEmpty ||
        note.length > 250) {
      throw ArgumentError(
        'İşlem kimliği ve en fazla 250 karakterlik gerekçe zorunludur.',
      );
    }
    if (correction.type == PaymentTransactionType.collection ||
        correction.method == PaymentMethod.credit) {
      throw ArgumentError('Geçersiz düzeltme türü veya ödeme yöntemi.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final prior = await txn.query(
        'payment_transactions',
        where: 'operationId=?',
        whereArgs: [key],
      );
      if (prior.isNotEmpty) {
        final original = PaymentTransaction.fromMap(prior.single);
        if (original.appointmentId != correction.appointmentId ||
            original.type != correction.type ||
            original.amountCents != correction.amountCents ||
            original.tipCents != correction.tipCents ||
            original.reversesTransactionId !=
                correction.reversesTransactionId ||
            original.method != correction.method ||
            original.note != note) {
          throw StateError(
            'İşlem kimliği başka bir düzeltme için kullanılmış.',
          );
        }
        return original.id!;
      }
      final account = await _getPaymentAccount(txn, correction.appointmentId);
      if (account == null || !account.supportsCorrections) {
        throw StateError('Düzeltilebilir ödeme kaydı bulunamadı.');
      }
      if (correction.reversesTransactionId != null) {
        final originals = await txn.query(
          'payment_transactions',
          where: 'id=? AND appointmentId=?',
          whereArgs: [
            correction.reversesTransactionId,
            correction.appointmentId,
          ],
        );
        if (originals.isEmpty) {
          throw StateError('Geri alınacak düzeltme bulunamadı.');
        }
        final original = PaymentTransaction.fromMap(originals.single);
        if (original.reversesTransactionId != null ||
            original.type != correction.type ||
            original.amountCents != correction.amountCents ||
            original.tipCents != correction.tipCents ||
            original.method != correction.method) {
          throw StateError(
            'Yalnız özgün düzeltmenin tamamı, aynı yöntem ve tutarla geri alınabilir.',
          );
        }
        final reversals = await txn.query(
          'payment_transactions',
          columns: ['id'],
          where: 'reversesTransactionId=?',
          whereArgs: [original.id],
        );
        if (reversals.isNotEmpty) {
          throw StateError('Bu düzeltme zaten geri alınmış.');
        }
        return txn.insert(
          'payment_transactions',
          correction.toMap()..remove('id'),
        );
      }
      if (correction.type == PaymentTransactionType.refund) {
        if (correction.serviceCents > account.refundableServiceCents ||
            correction.tipCents > account.refundableTipCents) {
          throw StateError('İade kalan hizmet veya bahşiş tahsilatını aşamaz.');
        }
      } else {
        if (correction.method != PaymentMethod.other ||
            correction.amountCents > account.outstandingCents) {
          throw StateError(
            'Borçtan düşme kalan veresiyeyi aşamaz; para hareketi oluşturmaz.',
          );
        }
      }
      return txn.insert(
        'payment_transactions',
        correction.toMap()..remove('id'),
      );
    });
  }

  Future<List<PaymentTransaction>> getPaymentTransactionsForAppointment(
    int appointmentId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'payment_transactions',
      where: 'appointmentId = ?',
      whereArgs: [appointmentId],
      orderBy: 'occurredAt ASC, id ASC',
    );
    return rows.map(PaymentTransaction.fromMap).toList();
  }

  Future<int> getOutstandingBalanceForAppointment(int appointmentId) async {
    return (await getPaymentAccount(appointmentId))?.outstandingCents ?? 0;
  }

  Future<List<Receivable>> getOpenReceivables() async {
    final db = await database;
    return _getOpenReceivables(db);
  }

  Future<List<Receivable>> _getOpenReceivables(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''
      SELECT
        p.appointmentId AS appointmentId,
        a.customerName AS customerName,
        a.serviceName AS serviceName,
        a.appointmentDate AS appointmentDate,
        p.amountCents AS originalAmountCents,
        COALESCE(SUM(
          CASE WHEN t.type = 'collection' THEN t.amountCents ELSE 0 END
        ), 0) AS collectedCents,
        COALESCE(SUM(CASE WHEN t.type = 'refund' THEN (t.amountCents - t.tipCents) * CASE WHEN t.reversesTransactionId IS NULL THEN 1 ELSE -1 END ELSE 0 END), 0) AS refundedCents,
        COALESCE(SUM(CASE WHEN t.type = 'adjustment' THEN t.amountCents * CASE WHEN t.reversesTransactionId IS NULL THEN 1 ELSE -1 END ELSE 0 END), 0) AS waivedCents,
        p.amountCents - COALESCE(SUM(
          CASE WHEN t.type = 'collection' THEN t.amountCents WHEN t.type = 'adjustment' THEN t.amountCents * CASE WHEN t.reversesTransactionId IS NULL THEN 1 ELSE -1 END ELSE 0 END
        ), 0) AS outstandingCents
      FROM payments p
      INNER JOIN appointments a ON a.id = p.appointmentId
      LEFT JOIN payment_transactions t ON t.appointmentId = p.appointmentId
      WHERE p.status = 'pending'
      GROUP BY p.id, p.appointmentId, a.customerName, a.serviceName,
               a.appointmentDate, p.amountCents
      HAVING outstandingCents > 0
      ORDER BY a.appointmentDate ASC, a.appointmentTime ASC
    ''');
    return rows.map(Receivable.fromMap).toList();
  }

  Future<List<PaymentTransaction>> getPaymentTransactionsForDate(
    DateTime date,
  ) async {
    final db = await database;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().split('T').first;
    final end = DateTime(
      date.year,
      date.month,
      date.day + 1,
    ).toIso8601String().split('T').first;
    final rows = await db.query(
      'payment_transactions',
      where: 'occurredAt >= ? AND occurredAt < ?',
      whereArgs: [start, end],
      orderBy: 'occurredAt ASC, id ASC',
    );
    return rows.map(PaymentTransaction.fromMap).toList();
  }

  Future<CashReport> getCashReport(DateTime startDate, DateTime endDate) async {
    final db = await database;
    return db.transaction((txn) async {
      final start = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).toIso8601String().split('T').first;
      final end = DateTime(
        endDate.year,
        endDate.month,
        endDate.day + 1,
      ).toIso8601String().split('T').first;
      final paymentRows = await txn.query(
        'payments',
        where: "status = 'paid' AND paidAt >= ? AND paidAt < ?",
        whereArgs: [start, end],
        orderBy: 'paidAt ASC, id ASC',
      );
      final transactionRows = await txn.query(
        'payment_transactions',
        where: 'occurredAt >= ? AND occurredAt < ?',
        whereArgs: [start, end],
        orderBy: 'occurredAt ASC, id ASC',
      );
      final receivables = await _getOpenReceivables(txn);
      return CashReport.fromEntries(
        payments: paymentRows.map(Payment.fromMap),
        transactions: transactionRows.map(PaymentTransaction.fromMap),
        outstandingCents: receivables.fold(
          0,
          (sum, item) => sum + item.outstandingCents,
        ),
      );
    });
  }

  Future<List<Payment>> getPaymentsForDate(DateTime date) async {
    final db = await database;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().split('T').first;
    final end = DateTime(
      date.year,
      date.month,
      date.day + 1,
    ).toIso8601String().split('T').first;
    final rows = await db.rawQuery(
      '''
      SELECT p.* FROM payments p
      WHERE p.status = 'paid'
        AND p.paidAt >= ? AND p.paidAt < ?
      ORDER BY p.paidAt ASC
      ''',
      [start, end],
    );
    return rows.map(Payment.fromMap).toList();
  }

  // ==================== SERVICE CRUD ====================

  Future<int> insertService(BarberService service) async {
    final db = await database;
    return db.insert('services', service.toMap());
  }

  Future<List<BarberService>> getServices({bool activeOnly = true}) async {
    final db = await database;
    final result = await db.query(
      'services',
      where: activeOnly ? 'isActive = 1' : null,
      orderBy: 'name ASC',
    );
    return result.map(BarberService.fromMap).toList();
  }

  Future<int> updateService(BarberService service) async {
    if (service.id == null) {
      throw ArgumentError('Düzenlenecek hizmetin kimliği gerekli.');
    }
    final db = await database;
    return db.update(
      'services',
      service.toMap(),
      where: 'id = ?',
      whereArgs: [service.id],
    );
  }

  // ==================== HAIRSTYLE TEMPLATE CRUD ====================

  Future<int> insertHairstyleTemplate(HairstyleTemplate template) async {
    final db = await database;
    return db.insert('hairstyle_templates', template.toMap()..remove('id'));
  }

  Future<List<HairstyleTemplate>> getHairstyleTemplates() async {
    final db = await database;
    final rows = await db.query(
      'hairstyle_templates',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(HairstyleTemplate.fromMap).toList();
  }

  // ==================== WORKING SCHEDULE ====================

  Future<int> getAppointmentCapacity() async {
    final db = await database;
    final row = await db.query(
      'shop_settings',
      columns: ['appointmentCapacity'],
      where: 'id = 1',
      limit: 1,
    );
    return row.isEmpty ? 1 : row.single['appointmentCapacity'] as int;
  }

  Future<void> setAppointmentCapacity(int capacity) async {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
    final db = await database;
    await db.update('shop_settings', {
      'appointmentCapacity': capacity,
    }, where: 'id = 1');
  }

  Future<bool> isPaymentEnabled() async {
    final db = await database;
    final row = await db.query(
      'shop_settings',
      columns: ['paymentEnabled'],
      where: 'id = 1',
      limit: 1,
    );
    return row.isEmpty || row.single['paymentEnabled'] == 1;
  }

  Future<void> setPaymentEnabled(bool enabled) async {
    final db = await database;
    await db.update('shop_settings', {
      'paymentEnabled': enabled ? 1 : 0,
    }, where: 'id = 1');
  }

  Future<List<WorkingInterval>> getWorkingIntervals() async {
    final db = await database;
    final rows = await db.query(
      'working_hours',
      orderBy: 'weekday ASC, startMinute ASC',
    );
    return rows.map(WorkingInterval.fromMap).toList();
  }

  Future<void> replaceWorkingIntervals(List<WorkingInterval> intervals) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('working_hours');
      for (final interval in intervals) {
        await txn.insert('working_hours', interval.toMap());
      }
    });
  }

  Future<List<ClosedTimeBlock>> getClosedTimeBlocks() async {
    final db = await database;
    final rows = await db.query('closed_time_blocks', orderBy: 'startAt ASC');
    return rows.map(ClosedTimeBlock.fromMap).toList();
  }

  Future<int> insertClosedTimeBlock(ClosedTimeBlock block) async {
    final db = await database;
    return db.insert('closed_time_blocks', block.toMap());
  }

  Future<int> deleteClosedTimeBlock(int id) async {
    final db = await database;
    return db.delete('closed_time_blocks', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== CUSTOMER CRUD ====================

  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return await db.insert('customers', customer.toMap());
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final result = await db.query('customers', orderBy: 'name ASC');
    return result.map((map) => Customer.fromMap(map)).toList();
  }

  String _normalizeTurkish(String text) {
    return text
        .replaceAll('I', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('Ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('Ş', 's')
        .replaceAll('Ö', 'o')
        .replaceAll('Ç', 'c')
        .toLowerCase()
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('\u0307', '');
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final allCustomers = await getAllCustomers();
    if (query.trim().isEmpty) return allCustomers;

    final normalizedQuery = _normalizeTurkish(query.trim());
    return allCustomers.where((c) {
      final normalizedName = _normalizeTurkish(c.name);
      final phone = c.phone ?? '';
      return normalizedName.contains(normalizedQuery) ||
          phone.contains(query.trim());
    }).toList();
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await database;
    final result = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return Customer.fromMap(result.first);
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await database;
    return db.transaction((txn) => _updateCustomer(txn, customer));
  }

  Future<int> _updateCustomer(DatabaseExecutor db, Customer customer) async {
    final rowCount = await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    // Sync customer name to appointments table
    if (customer.id != null) {
      await db.update(
        'appointments',
        {'customerName': customer.name},
        where: 'customerId = ?',
        whereArgs: [customer.id],
      );
    }
    return rowCount;
  }

  Future<Customer> resolveAppointmentCustomer({
    int? selectedCustomerId,
    required String name,
    required String phone,
  }) async {
    final db = await database;
    return db.transaction(
      (txn) => _resolveAppointmentCustomer(
        txn,
        selectedCustomerId: selectedCustomerId,
        name: name,
        phone: phone,
      ),
    );
  }

  Future<Customer> _resolveAppointmentCustomer(
    DatabaseExecutor db, {
    int? selectedCustomerId,
    required String name,
    required String phone,
  }) async {
    if (selectedCustomerId == null) {
      if (name.trim().isEmpty) throw ArgumentError('Müşteri adı gerekli.');
      final customer = Customer(
        name: name.trim(),
        phone: phone.trim().isEmpty ? null : phone.trim(),
      );
      final id = await db.insert('customers', customer.toMap()..remove('id'));
      return customer.copyWith(id: id);
    }
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [selectedCustomerId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Seçilen müşteri bulunamadı.');
    var customer = Customer.fromMap(rows.single);
    if (phone.trim().isNotEmpty && customer.phone != phone.trim()) {
      customer = customer.copyWith(phone: phone.trim());
      await _updateCustomer(db, customer);
    }
    return customer;
  }

  /// The complete form save is one transaction; no orphan customer or partial edit.
  Future<Appointment> saveAppointmentForCustomer({
    required Appointment appointment,
    int? selectedCustomerId,
    required String phone,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      // Recheck capacity inside the write transaction, after the UI's preview.
      if (appointment.isActive) {
        final date = appointment.appointmentDate
            .toIso8601String()
            .split('T')
            .first;
        final rows = await txn.query(
          'appointments',
          where: 'appointmentDate LIKE ?',
          whereArgs: ['$date%'],
        );
        final settings = await txn.query(
          'shop_settings',
          columns: ['appointmentCapacity'],
          limit: 1,
        );
        final capacity =
            settings.firstOrNull?['appointmentCapacity'] as int? ?? 1;
        if (appointmentExceedsCapacity(
          appointment,
          rows.map(Appointment.fromMap).where((a) => a.id != appointment.id),
          capacity: capacity,
        )) {
          throw StateError('Bu saatte zaten bir randevu var!');
        }
      }
      final customer = await _resolveAppointmentCustomer(
        txn,
        selectedCustomerId: selectedCustomerId,
        name: appointment.customerName,
        phone: phone,
      );
      final resolved = appointment.copyWith(
        customerId: customer.id,
        customerName: customer.name,
      );
      if (resolved.id == null) {
        final id = await _insertAppointment(txn, resolved);
        return resolved.copyWith(id: id);
      }
      final updated = await _updateAppointment(txn, resolved);
      if (updated != 1) throw StateError('Randevu bulunamadı.');
      return resolved;
    });
  }

  Future<int> addCustomerPhoto(CustomerPhoto photo) async {
    final db = await database;
    return db.transaction((txn) => _addCustomerPhoto(txn, photo));
  }

  Future<int> _addCustomerPhoto(
    DatabaseExecutor txn,
    CustomerPhoto photo,
  ) async {
    final customer = await txn.query(
      'customers',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [photo.customerId],
      limit: 1,
    );
    if (customer.isEmpty) throw StateError('Müşteri bulunamadı.');
    final id = await txn.insert('customer_photos', photo.toMap()..remove('id'));
    await txn.update(
      'customers',
      {'photoPath': photo.photoPath},
      where: 'id = ?',
      whereArgs: [photo.customerId],
    );
    return id;
  }

  Future<int> saveCustomerWithPhoto(
    Customer customer, {
    String? newPhotoPath,
    CustomerPhotoType photoType = CustomerPhotoType.reference,
    CustomerPhotoSource photoSource = CustomerPhotoSource.gallery,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      int id;
      if (customer.id == null) {
        id = await txn.insert('customers', customer.toMap()..remove('id'));
      } else {
        id = customer.id!;
        if (await _updateCustomer(txn, customer) != 1) {
          throw StateError('Müşteri bulunamadı.');
        }
      }
      if (newPhotoPath != null) {
        await _addCustomerPhoto(
          txn,
          CustomerPhoto(
            customerId: id,
            photoPath: newPhotoPath,
            type: photoType,
            source: photoSource,
          ),
        );
      }
      return id;
    });
  }

  Future<List<CustomerPhoto>> getCustomerPhotos(int customerId) async {
    final db = await database;
    final rows = await db.query(
      'customer_photos',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'createdAt DESC, id DESC',
    );
    return rows.map(CustomerPhoto.fromMap).toList();
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    final primaryPhotoRows = await db.query(
      'customers',
      columns: ['photoPath'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final historyPhotoRows = await db.query(
      'customer_photos',
      columns: ['photoPath'],
      where: 'customerId = ?',
      whereArgs: [id],
    );
    final photoPaths = <String>{
      for (final row in primaryPhotoRows)
        if (row['photoPath'] is String &&
            (row['photoPath'] as String).isNotEmpty)
          row['photoPath'] as String,
      for (final row in historyPhotoRows)
        if (row['photoPath'] is String &&
            (row['photoPath'] as String).isNotEmpty)
          row['photoPath'] as String,
    };

    final deleted = await db.transaction((txn) async {
      // Randevu geçmişi korunur; yalnızca müşteri kartıyla bağlantı kaldırılır.
      await txn.update(
        'appointments',
        {'customerId': null},
        where: 'customerId = ?',
        whereArgs: [id],
      );
      return txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });

    if (deleted == 1) {
      for (final photoPath in photoPaths) {
        await CustomerPhotoStorage.deleteManagedPhoto(photoPath);
      }
    }
    return deleted;
  }

  Future<void> updateCustomerStats(int customerId) async {
    final db = await database;
    await db.transaction((txn) => _updateCustomerStats(txn, customerId));
  }

  Future<void> _updateCustomerStats(DatabaseExecutor db, int customerId) async {
    // Count total appointments
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM appointments WHERE customerId = ?',
      [customerId],
    );
    final totalAppointments = Sqflite.firstIntValue(countResult) ?? 0;

    // Get latest appointment date
    final latestResult = await db.rawQuery(
      'SELECT appointmentDate FROM appointments WHERE customerId = ? ORDER BY appointmentDate DESC LIMIT 1',
      [customerId],
    );
    String? lastDate;
    if (latestResult.isNotEmpty) {
      lastDate = latestResult.first['appointmentDate'] as String?;
    }

    // Find most used hairstyle
    final hairstyleResult = await db.rawQuery(
      'SELECT hairstyleName, COUNT(*) as count FROM appointments WHERE customerId = ? AND hairstyleName IS NOT NULL GROUP BY hairstyleName ORDER BY count DESC LIMIT 1',
      [customerId],
    );
    String? favoriteHairstyle;
    if (hairstyleResult.isNotEmpty) {
      favoriteHairstyle = hairstyleResult.first['hairstyleName'] as String?;
    }

    await db.update(
      'customers',
      {
        'totalAppointments': totalAppointments,
        'lastAppointmentDate': lastDate,
        'favoriteHairstyle': favoriteHairstyle,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  // ==================== APPOINTMENT CRUD ====================

  Future<int> insertAppointment(Appointment appointment) async {
    final db = await database;
    return db.transaction((txn) => _insertAppointment(txn, appointment));
  }

  Future<int> _insertAppointment(
    DatabaseExecutor db,
    Appointment appointment,
  ) async {
    final id = await db.insert('appointments', appointment.toMap());

    // Update customer stats
    if (appointment.customerId != null) {
      await _updateCustomerStats(db, appointment.customerId!);
    }

    return id;
  }

  Future<List<Appointment>> getAppointmentsByDate(DateTime date) async {
    final db = await database;
    final datePrefix =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    // Legacy and imported databases may store midnight without milliseconds,
    // while Dart's ISO formatter uses ".000". Match the calendar day prefix so
    // both stable date representations remain readable.
    final result = await db.query(
      'appointments',
      where: 'appointmentDate LIKE ?',
      whereArgs: ['$datePrefix%'],
      orderBy: 'appointmentTime ASC',
    );
    return result.map((map) => Appointment.fromMap(map)).toList();
  }

  Future<List<Appointment>> getAppointmentsForCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'appointments',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'appointmentDate DESC, appointmentTime DESC',
    );
    return result.map((map) => Appointment.fromMap(map)).toList();
  }

  Future<List<Appointment>> getUpcomingAppointments() async {
    final db = await database;
    final now = DateTime.now();
    final todayPrefix =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final result = await db.query(
      'appointments',
      where:
          'appointmentDate >= ? AND isCompleted = 0 AND status NOT IN (?, ?)',
      whereArgs: [
        todayPrefix,
        AppointmentStatus.cancelled.value,
        AppointmentStatus.noShow.value,
      ],
      orderBy: 'appointmentDate ASC, appointmentTime ASC',
    );
    return result.map((map) => Appointment.fromMap(map)).toList();
  }

  Future<List<Appointment>> searchAppointments(String query) async {
    final db = await database;
    final normalizedSearch = _normalizeTurkish(query);

    final result = await db.query(
      'appointments',
      orderBy: 'appointmentDate DESC, appointmentTime DESC',
    );
    final all = result.map((map) => Appointment.fromMap(map)).toList();
    if (normalizedSearch.isEmpty) return all;

    return all
        .where(
          (a) => _normalizeTurkish(a.customerName).contains(normalizedSearch),
        )
        .toList();
  }

  Future<int> updateAppointment(Appointment appointment) async {
    final db = await database;
    return db.transaction((txn) => _updateAppointment(txn, appointment));
  }

  Future<int> _updateAppointment(
    DatabaseExecutor db,
    Appointment appointment,
  ) async {
    // Check if customer ID changed to update old customer's stats
    final oldResult = await db.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [appointment.id],
    );
    int? oldCustomerId;
    if (oldResult.isNotEmpty) {
      oldCustomerId = oldResult.first['customerId'] as int?;
    }

    final result = await db.update(
      'appointments',
      appointment.toMap(),
      where: 'id = ?',
      whereArgs: [appointment.id],
    );

    if (appointment.customerId != null) {
      await _updateCustomerStats(db, appointment.customerId!);
    }
    if (oldCustomerId != null && oldCustomerId != appointment.customerId) {
      await _updateCustomerStats(db, oldCustomerId);
    }

    return result;
  }

  Future<int> setAppointmentStatus(int id, AppointmentStatus status) async {
    final db = await database;
    return db.transaction((txn) async {
      final result = await txn.update(
        'appointments',
        {
          'isCompleted': status == AppointmentStatus.completed ? 1 : 0,
          'status': status.value,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      final rows = await txn.query(
        'appointments',
        columns: ['customerId'],
        where: 'id = ?',
        whereArgs: [id],
      );
      final customerId = rows.firstOrNull?['customerId'] as int?;
      if (customerId != null) await _updateCustomerStats(txn, customerId);
      return result;
    });
  }

  Future<int> toggleAppointmentCompletion(int id, bool isCompleted) async {
    return setAppointmentStatus(
      id,
      isCompleted ? AppointmentStatus.completed : AppointmentStatus.planned,
    );
  }

  Future<int> deleteAppointment(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final payments = await txn.query(
        'payments',
        columns: ['status'],
        where: 'appointmentId=?',
        whereArgs: [id],
      );
      if (payments.any((p) => p['status'] != PaymentStatus.unknown.value)) {
        throw StateError(
          'Finansal kaydı olan randevu silinemez. Durum değiştirin veya düzeltme hareketi ekleyin.',
        );
      }
      final rows = await txn.query(
        'appointments',
        columns: ['customerId'],
        where: 'id=?',
        whereArgs: [id],
      );
      final deleted = await txn.delete(
        'appointments',
        where: 'id=?',
        whereArgs: [id],
      );
      final customerId = rows.firstOrNull?['customerId'] as int?;
      if (customerId != null) await _updateCustomerStats(txn, customerId);
      return deleted;
    });
  }

  Future<Appointment?> getAppointmentById(int id) async {
    final db = await database;
    final result = await db.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return Appointment.fromMap(result.first);
  }

  // Check if there's already an appointment at the given time
  Future<bool> isTimeSlotTaken(
    DateTime date,
    String time, {
    int durationMinutes = 30,
    int? excludeId,
  }) async {
    final appointments = await getAppointmentsByDate(date);
    final candidate = Appointment(
      customerName: 'Çakışma kontrolü',
      appointmentDate: date,
      appointmentTime: time,
      durationMinutes: durationMinutes,
    );

    final capacity = await getAppointmentCapacity();
    return appointmentExceedsCapacity(
      candidate,
      appointments.where((appointment) => appointment.id != excludeId),
      capacity: capacity,
    );
  }
}

/// A scoped connection capability valid only inside withMaintenance.
class DatabaseMaintenance {
  DatabaseMaintenance._(this._open, this._close, this._markReplaced);
  final Future<Database> Function() _open;
  final Future<void> Function() _close;
  final void Function() _markReplaced;
  bool _active = true;
  void _check() {
    if (!_active) throw StateError('Bakım işlemi tamamlandı.');
  }

  Future<Database> open() {
    _check();
    return _open();
  }

  Future<void> close() {
    _check();
    return _close();
  }

  void markReplaced() {
    _check();
    _markReplaced();
  }
}
