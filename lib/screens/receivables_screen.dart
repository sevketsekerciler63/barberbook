import '../utils/money.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/payment.dart';
import '../models/payment_transaction.dart';
import '../models/receivable.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';

class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  bool _loading = true;
  String? _error;
  List<Receivable> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await DatabaseService.instance.getOpenReceivables();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _money(int cents) => '${(cents / 100).toStringAsFixed(2)} ₺';

  Future<void> _collect(Receivable item) async {
    final transaction = await showDialog<PaymentTransaction>(
      context: context,
      builder: (_) => _CollectionDialog(item: item),
    );
    if (transaction == null) return;
    try {
      await DatabaseService.instance.recordPaymentTransaction(transaction);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tahsilat kaydedildi.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tahsilat kaydedilemedi: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Açık veresiyeler')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Veresiyeler yüklenemedi.'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            )
          : _items.isEmpty
          ? const Center(child: Text('Açık veresiye bulunmuyor.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    color: AppColors.surface,
                    child: ListTile(
                      title: Text(item.customerName),
                      subtitle: Text(
                        '${item.serviceName ?? 'Hizmet'} • ${DateFormat('dd.MM.yyyy').format(item.appointmentDate)}\n'
                        'Toplam ${_money(item.originalAmountCents)} • Tahsil ${_money(item.collectedCents)}',
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _money(item.outstandingCents),
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text('Kalan'),
                        ],
                      ),
                      onTap: () => _collect(item),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CollectionDialog extends StatefulWidget {
  final Receivable item;
  const _CollectionDialog({required this.item});
  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  String? _error;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: (widget.item.outstandingCents / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (_submitted) return;
    final cents = parseMoneyCents(_amount.text, emptyAsZero: false);
    if (cents == null || cents <= 0 || cents > widget.item.outstandingCents) {
      setState(
        () => _error = 'Tutar sıfırdan büyük ve kalan borcu aşmamalıdır.',
      );
      return;
    }
    _submitted = true;
    Navigator.pop(
      context,
      PaymentTransaction(
        appointmentId: widget.item.appointmentId,
        type: PaymentTransactionType.collection,
        amountCents: cents,
        method: _method,
        occurredAt: DateTime.now(),
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Veresiye tahsil et'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.item.customerName} • Kalan ${(widget.item.outstandingCents / 100).toStringAsFixed(2)} ₺',
          ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Tahsil edilen (₺)'),
          ),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Ödeme yöntemi'),
            items: PaymentMethod.values
                .where((method) => method != PaymentMethod.credit)
                .map(
                  (method) => DropdownMenuItem(
                    value: method,
                    child: Text(method.label),
                  ),
                )
                .toList(),
            onChanged: (method) {
              if (method != null) setState(() => _method = method);
            },
          ),
          TextField(
            controller: _note,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Not (opsiyonel)'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(onPressed: _save, child: const Text('Tahsilatı kaydet')),
    ],
  );
}
