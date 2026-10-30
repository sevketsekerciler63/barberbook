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

class DatabaseService {
  static Database? _database;
  static final DatabaseService instance = DatabaseService._init();

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('barberbook.db');
    return _database!;
  }

  Future<void> closeDatabase() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: 12,
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
    if (existing.first['status'] == PaymentStatus.pending.value) {
      throw StateError(
        'Veresiye kaydı değiştirilemez; tahsilat hareketi ekleyin.',
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

      final collected =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''
              SELECT COALESCE(SUM(amountCents), 0)
              FROM payment_transactions
              WHERE appointmentId = ? AND type = 'collection'
              ''',
              [transaction.appointmentId],
            ),
          ) ??
          0;
      final total = paymentRows.first['amountCents'] as int;
      if (transaction.amountCents > total - collected) {
        throw StateError('Tahsilat açık veresiye tutarını aşamaz.');
      }
      return txn.insert(
        'payment_transactions',
        transaction.toMap()..remove('id'),
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
    final db = await database;
    final paymentRows = await db.query(
      'payments',
      columns: ['amountCents', 'status'],
      where: 'appointmentId = ?',
      whereArgs: [appointmentId],
      limit: 1,
    );
    if (paymentRows.isEmpty ||
        paymentRows.first['status'] != PaymentStatus.pending.value) {
      return 0;
    }
    final collected =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COALESCE(SUM(amountCents), 0)
            FROM payment_transactions
            WHERE appointmentId = ? AND type = 'collection'
            ''',
            [appointmentId],
          ),
        ) ??
        0;
    final total = paymentRows.first['amountCents'] as int;
    return total - collected;
  }

  Future<List<Receivable>> getOpenReceivables() async {
    final db = await database;
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
        p.amountCents - COALESCE(SUM(
          CASE WHEN t.type = 'collection' THEN t.amountCents ELSE 0 END
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
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day + 1).toIso8601String();
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
    final start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    ).toIso8601String();
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day + 1,
    ).toIso8601String();
    final paymentRows = await db.query(
      'payments',
      where: "status = 'paid' AND paidAt >= ? AND paidAt < ?",
      whereArgs: [start, end],
      orderBy: 'paidAt ASC, id ASC',
    );
    final transactionRows = await db.query(
      'payment_transactions',
      where: 'occurredAt >= ? AND occurredAt < ?',
      whereArgs: [start, end],
      orderBy: 'occurredAt ASC, id ASC',
    );
    final receivables = await getOpenReceivables();
    return CashReport.fromEntries(
      payments: paymentRows.map(Payment.fromMap),
      transactions: transactionRows.map(PaymentTransaction.fromMap),
      outstandingCents: receivables.fold(
        0,
        (sum, item) => sum + item.outstandingCents,
      ),
    );
  }

  Future<List<Payment>> getPaymentsForDate(DateTime date) async {
    final db = await database;
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day + 1).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT p.* FROM payments p
      INNER JOIN appointments a ON a.id = p.appointmentId
      WHERE a.status = 'completed'
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

  Future<int> addCustomerPhoto(CustomerPhoto photo) async {
    final db = await database;
    return db.transaction((txn) async {
      final customer = await txn.query(
        'customers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [photo.customerId],
        limit: 1,
      );
      if (customer.isEmpty) throw StateError('Müşteri bulunamadı.');
      final id = await txn.insert(
        'customer_photos',
        photo.toMap()..remove('id'),
      );
      await txn.update(
        'customers',
        {'photoPath': photo.photoPath},
        where: 'id = ?',
        whereArgs: [photo.customerId],
      );
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
    final id = await db.insert('appointments', appointment.toMap());

    // Update customer stats
    if (appointment.customerId != null) {
      await updateCustomerStats(appointment.customerId!);
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
      await updateCustomerStats(appointment.customerId!);
    }
    if (oldCustomerId != null && oldCustomerId != appointment.customerId) {
      await updateCustomerStats(oldCustomerId);
    }

    return result;
  }

  Future<int> setAppointmentStatus(int id, AppointmentStatus status) async {
    final db = await database;
    final result = await db.update(
      'appointments',
      {
        'isCompleted': status == AppointmentStatus.completed ? 1 : 0,
        'status': status.value,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final appointment = await getAppointmentById(id);
    if (appointment?.customerId != null) {
      await updateCustomerStats(appointment!.customerId!);
    }
    return result;
  }

  Future<int> toggleAppointmentCompletion(int id, bool isCompleted) async {
    return setAppointmentStatus(
      id,
      isCompleted ? AppointmentStatus.completed : AppointmentStatus.planned,
    );
  }

  Future<int> deleteAppointment(int id) async {
    final db = await database;

    // Get appointment first to update customer stats
    final result = await db.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
    );

    final deleted = await db.delete(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isNotEmpty) {
      final customerId = result.first['customerId'] as int?;
      if (customerId != null) {
        await updateCustomerStats(customerId);
      }
    }

    return deleted;
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
