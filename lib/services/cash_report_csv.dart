import 'package:intl/intl.dart';

import '../models/cash_report.dart';
import '../models/payment.dart';

class CashReportCsv {
  static String build(CashReport report, DateTime start, DateTime end) {
    final date = DateFormat('dd.MM.yyyy');
    String money(int cents) =>
        (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

    final lines = <String>[
      'Berber Randevu Kasa Raporu',
      'Başlangıç;${date.format(start)}',
      'Bitiş;${date.format(end)}',
      '',
      'Özet;Tutar (₺)',
      'Toplam tahsilat;${money(report.collectedCents)}',
      'Güncel açık veresiye;${money(report.outstandingCents)}',
      'İndirim;${money(report.discountCents)}',
      'Bahşiş;${money(report.tipCents)}',
      'Tahsilat adedi;${report.collectionCount}',
      '',
      'Ödeme yöntemi;Tutar (₺)',
    ];
    for (final method in PaymentMethod.values) {
      final amount = report.byMethod[method];
      if (amount != null && amount != 0) {
        lines.add('${method.label};${money(amount)}');
      }
    }
    return '${lines.join('\r\n')}\r\n';
  }
}
