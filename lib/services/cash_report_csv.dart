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
      'Hizmet iadesi;${money(report.refundedCents)}',
      'Tahsilat geri alma;${money(report.reversedCollectionCents)}',
      'Net hizmet;${money(report.netServiceCents)}',
      'Güncel açık veresiye;${money(report.outstandingCents)}',
      'İndirim;${money(report.discountCents)}',
      'Bahşiş;${money(report.tipCents)}',
      'Bahşiş iadesi;${money(report.refundedTipCents)}',
      'Net bahşiş;${money(report.netTipCents)}',
      'Net para hareketi;${money(report.netCashCents)}',
      'Borçtan düşülen (para hareketi yok);${money(report.waivedDebtCents)}',
      'Tahsilat adedi;${report.collectionCount}',
      'Tahsilat geri alma adedi;${report.collectionReversalCount}',
      '',
      'İade adedi;${report.refundCount}',
      'Ödeme yöntemi;Net hizmet tutarı (₺)',
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
