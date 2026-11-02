import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../models/payment.dart';
import '../utils/money.dart';
import 'receivables_screen.dart';
import 'payment_history_screen.dart';

Future<Payment?> showPaymentDialog(
  BuildContext context,
  Appointment appointment, {
  Payment? existing,
}) async {
  if (appointment.id == null) return null;
  // A credit balance is settled through append-only collections, never overwritten.
  if (existing?.status == PaymentStatus.pending) {
    final openReceivables = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kayıtlı veresiye'),
        content: const Text(
          'Bu randevunun veresiye kaydı var. Tahsilatları Veresiyeler ekranından kaydedin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Veresiyelere git'),
          ),
        ],
      ),
    );
    if (openReceivables == true && context.mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ReceivablesScreen()));
    }
    return null;
  }
  if (existing != null && existing.status != PaymentStatus.unknown) {
    final openHistory = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tahsilat zaten kayıtlı'),
        content: const Text(
          'Randevu durumunu değiştirmek alınmış tahsilatı değiştirmez. Kayıtlı ödeme bu formdan yeniden yazılamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('İade / borç düzeltme'),
          ),
        ],
      ),
    );
    if (openHistory == true && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentAccountScreen(appointmentId: appointment.id!),
        ),
      );
    }
    return null;
  }
  return showDialog<Payment>(
    context: context,
    builder: (_) =>
        _PaymentDialog(appointment: appointment, existing: existing),
  );
}

class _PaymentDialog extends StatefulWidget {
  final Appointment appointment;
  final Payment? existing;
  const _PaymentDialog({required this.appointment, this.existing});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _discount;
  late final TextEditingController _tip;
  late final TextEditingController _note;
  late PaymentMethod _method;
  String? _error;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(
      text: existing != null
          ? ((existing.amountCents + existing.discountCents) / 100)
                .toStringAsFixed(2)
          : widget.appointment.priceCents == null
          ? ''
          : (widget.appointment.priceCents! / 100).toStringAsFixed(2),
    );
    _discount = TextEditingController(
      text: ((existing?.discountCents ?? 0) / 100).toStringAsFixed(2),
    );
    _tip = TextEditingController(
      text: ((existing?.tipCents ?? 0) / 100).toStringAsFixed(2),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _method = existing?.method ?? PaymentMethod.cash;
  }

  @override
  void dispose() {
    _amount.dispose();
    _discount.dispose();
    _tip.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (_submitted) return;
    final amount = parseMoneyCents(_amount.text);
    final discount = parseMoneyCents(_discount.text);
    final tip = parseMoneyCents(_tip.text);
    if (amount == null ||
        discount == null ||
        tip == null ||
        discount > amount) {
      setState(
        () => _error =
            'Tutarları en fazla iki ondalık basamakla girin. İndirim hizmet bedelini aşamaz.',
      );
      return;
    }
    final credit = _method == PaymentMethod.credit;
    if (credit && (amount - discount <= 0 || tip != 0)) {
      setState(
        () => _error =
            'Veresiye tutarı sıfırdan büyük olmalıdır. Veresiyeye bahşiş eklenemez.',
      );
      return;
    }
    final existing = widget.existing;
    _submitted = true;
    Navigator.pop(
      context,
      Payment(
        id: existing?.id,
        appointmentId: widget.appointment.id!,
        amountCents: amount - discount,
        discountCents: discount,
        tipCents: tip,
        status: credit ? PaymentStatus.pending : PaymentStatus.paid,
        method: _method,
        paidAt: credit ? null : existing?.paidAt ?? DateTime.now(),
        note: _note.text,
        createdAt: existing?.createdAt,
      ),
    );
  }

  Widget _moneyField(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tahsilat kaydı'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.appointment.customerName} • ${widget.appointment.serviceName ?? 'Hizmet'}',
            ),
            const SizedBox(height: 16),
            _moneyField('Hizmet bedeli (indirim öncesi, ₺)', _amount),
            _moneyField('İndirim (₺)', _discount),
            _moneyField('Bahşiş (₺, hizmet bedelinden ayrı)', _tip),
            const Text(
              'Kaydedilen hizmet tutarı = bedel − indirim. Bahşiş raporda ayrıca gösterilir.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in const [
                  PaymentMethod.cash,
                  PaymentMethod.card,
                  PaymentMethod.transfer,
                  PaymentMethod.credit,
                ])
                  ChoiceChip(
                    label: Text(method.label),
                    selected: _method == method,
                    onSelected: (_) => setState(() {
                      _method = method;
                      _error = null;
                    }),
                  ),
              ],
            ),
            if (_method == PaymentMethod.credit)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Bu tutar henüz tahsil edilmez; açık veresiye olarak kaydedilir.',
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Ödeme notu (opsiyonel)',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(onPressed: _save, child: const Text('Kaydet')),
    ],
  );
}
