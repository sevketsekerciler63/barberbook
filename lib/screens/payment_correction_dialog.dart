import 'package:flutter/material.dart';
import '../models/payment.dart';
import '../models/payment_account.dart';
import '../models/payment_transaction.dart';
import '../utils/money.dart';

Future<PaymentTransaction?> showPaymentReversalDialog(
  BuildContext context,
  PaymentTransaction original,
) async {
  if (original.id == null) return null;
  return showDialog<PaymentTransaction>(
    context: context,
    builder: (_) => _ReversalDialog(original: original),
  );
}

class _ReversalDialog extends StatefulWidget {
  final PaymentTransaction original;
  const _ReversalDialog({required this.original});
  @override
  State<_ReversalDialog> createState() => _ReversalDialogState();
}

class _ReversalDialogState extends State<_ReversalDialog> {
  final _reason = TextEditingController();
  final _key = PaymentTransaction.newOperationId();
  bool _submitted = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.original.type == PaymentTransactionType.collection
          ? 'Tahsilatı geri al'
          : 'Düzeltmeyi geri al',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(widget.original.amountCents / 100).toStringAsFixed(2)} ₺ tutarındaki hareket geçmişten silinmez. '
            '${switch (widget.original.type) {
              PaymentTransactionType.refund => 'İade geri alınır; net tahsilat artar. Para geri alındıysa kaydedin.',
              PaymentTransactionType.adjustment => 'Borçtan düşme geri alınır; müşterinin açık borcu bu tutarda artar.',
              PaymentTransactionType.collection => 'Tahsilat kaydı geri alınır; net tahsilat azalır ve aynı tutar yeniden açık borç olur. Yanlış girilmiş tahsilatı düzeltmek içindir. Normal para iadesi borcu yeniden açmaz.',
            }}',
          ),
          TextField(
            controller: _reason,
            maxLength: 250,
            decoration: const InputDecoration(
              labelText: 'Geri alma gerekçesi (zorunlu)',
            ),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () {
          if (_submitted) return;
          final reason = _reason.text.trim();
          if (reason.isEmpty || reason.length > 250) {
            setState(() => _error = 'Geri alma gerekçesi girin.');
            return;
          }
          _submitted = true;
          final original = widget.original;
          Navigator.pop(
            context,
            PaymentTransaction(
              appointmentId: original.appointmentId,
              type: original.type,
              amountCents: original.amountCents,
              tipCents: original.tipCents,
              method: original.method,
              occurredAt: DateTime.now(),
              note: reason,
              operationId: _key,
              reversesTransactionId: original.id,
            ),
          );
        },
        child: const Text('Geri alma hareketini kaydet'),
      ),
    ],
  );
}

Future<PaymentTransaction?> showPaymentCorrectionDialog(
  BuildContext context,
  PaymentAccount account,
  PaymentTransactionType type,
) => showDialog<PaymentTransaction>(
  context: context,
  builder: (_) => _CorrectionDialog(account: account, type: type),
);

class _CorrectionDialog extends StatefulWidget {
  final PaymentAccount account;
  final PaymentTransactionType type;
  const _CorrectionDialog({required this.account, required this.type});
  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  late final TextEditingController _service;
  final _tip = TextEditingController(text: '0');
  final _reason = TextEditingController();
  final _operationId = PaymentTransaction.newOperationId();
  final _occurredAt = DateTime.now();
  PaymentMethod _method = PaymentMethod.cash;
  String? _error;
  bool _submitted = false;
  bool get _refund => widget.type == PaymentTransactionType.refund;
  String _money(int cents) => (cents / 100).toStringAsFixed(2);
  @override
  void initState() {
    super.initState();
    _service = TextEditingController(
      text: _money(
        _refund
            ? widget.account.refundableServiceCents
            : widget.account.outstandingCents,
      ),
    );
    final method = widget.account.payment.method;
    if (method != PaymentMethod.credit) _method = method;
  }

  @override
  void dispose() {
    _service.dispose();
    _tip.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    final service = parseMoneyCents(_service.text);
    final tip = _refund ? parseMoneyCents(_tip.text) : 0;
    final reason = _reason.text.trim();
    if (service == null ||
        tip == null ||
        service + tip <= 0 ||
        reason.isEmpty ||
        reason.length > 250) {
      setState(() => _error = 'Geçerli bir tutar ve işlem gerekçesi girin.');
      return;
    }
    if ((_refund &&
            (service > widget.account.refundableServiceCents ||
                tip > widget.account.refundableTipCents)) ||
        (!_refund && service > widget.account.outstandingCents)) {
      setState(
        () => _error = 'Tutar kalan iade veya veresiye sınırını aşamaz.',
      );
      return;
    }
    _submitted = true;
    Navigator.pop(
      context,
      PaymentTransaction(
        appointmentId: widget.account.appointmentId,
        type: widget.type,
        amountCents: service + tip,
        tipCents: tip,
        method: _refund ? _method : PaymentMethod.other,
        occurredAt: _occurredAt,
        note: reason,
        operationId: _operationId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_refund ? 'Para iadesi' : 'Borçtan düş'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.account.customerName),
            const SizedBox(height: 12),
            Text(
              _refund
                  ? 'Kalan iade: hizmet ${_money(widget.account.refundableServiceCents)} ₺, bahşiş ${_money(widget.account.refundableTipCents)} ₺. İade açık borcu artırmaz.'
                  : 'Kalan veresiye ${_money(widget.account.outstandingCents)} ₺. Bu işlem borcu azaltır; tahsilat veya para iadesi oluşturmaz.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _service,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _refund
                    ? 'Hizmet iadesi (₺)'
                    : 'Borçtan düşülecek tutar (₺)',
              ),
            ),
            if (_refund) ...[
              TextField(
                controller: _tip,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Bahşiş iadesi (₺)',
                ),
              ),
              const SizedBox(height: 12),
              const Text('Paranın gerçekten iade edildiği yöntem'),
              Wrap(
                spacing: 8,
                children: [
                  for (final method in PaymentMethod.values.where(
                    (m) => m != PaymentMethod.credit,
                  ))
                    ChoiceChip(
                      label: Text(method.label),
                      selected: method == _method,
                      onSelected: (_) => setState(() => _method = method),
                    ),
                ],
              ),
            ],
            TextField(
              controller: _reason,
              maxLength: 250,
              decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu)'),
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
      FilledButton(onPressed: _submit, child: const Text('Devam')),
    ],
  );
}
