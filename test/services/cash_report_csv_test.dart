import 'package:berber_randevu/models/cash_report.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/services/cash_report_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV exports Turkish headers, dates and method totals', () {
    const report = CashReport(
      collectedCents: 65000,
      outstandingCents: 25000,
      discountCents: 5000,
      tipCents: 3000,
      collectionCount: 2,
      byMethod: {PaymentMethod.cash: 50000, PaymentMethod.card: 15000},
    );

    final csv = CashReportCsv.build(
      report,
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 21),
    );

    expect(csv, contains('Başlangıç;01.09.2026'));
    expect(csv, contains('Bitiş;21.09.2026'));
    expect(csv, contains('Toplam tahsilat;650,00'));
    expect(csv, contains('Nakit;500,00'));
    expect(csv, contains('Kart;150,00'));
    expect(csv, contains('Güncel açık veresiye;250,00'));
  });
}
