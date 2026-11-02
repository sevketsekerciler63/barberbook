import '../utils/money.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/payment.dart';
import '../models/payment_transaction.dart';
import '../models/receivable.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';
import 'payment_history_screen.dart';

class ReceivablesGateway {
  const ReceivablesGateway();
  Future<List<Receivable>> load() =>
      DatabaseService.instance.getOpenReceivables();
  Future<int> record(PaymentTransaction request) =>
      DatabaseService.instance.recordPaymentTransaction(request);
}

class ReceivablesScreen extends StatefulWidget {
  final ReceivablesGateway gateway;
  const ReceivablesScreen({
    super.key,
    this.gateway = const ReceivablesGateway(),
  });

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  bool _loading = true;
  String? _error;
  List<Receivable> _items = [];
  bool _savingCollection = false;
  PaymentTransaction? _pendingCollection;
  String? _collectionError;

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
      final items = await widget.gateway.load();
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
    if (_savingCollection || _pendingCollection != null) return;
    setState(() => _savingCollection = true);
    try {
      final transaction = await showDialog<PaymentTransaction>(
        context: context,
        builder: (_) => _CollectionDialog(item: item),
      );
      if (transaction == null || !mounted) return;
      setState(() => _pendingCollection = transaction);
      await _saveCollection();
    } finally {
      if (mounted) setState(() => _savingCollection = false);
    }
  }

  Future<void> _saveCollection() async {
    final request = _pendingCollection;
    if (request == null) return;
    try {
      await widget.gateway.record(request);
      _pendingCollection = null;
      _collectionError = null;
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tahsilat kaydedildi.')));
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _collectionError = error is StateError
              ? '${error.message} Aynı kaydı yeniden deneyin veya listeyi yenileyin.'
              : 'Tahsilatın sonucu alınamadı. Aynı kaydı yeniden deneyin veya listeyi yenileyin.',
        );
      }
    }
  }

  Future<void> _retryCollection() async {
    if (_savingCollection || _pendingCollection == null) return;
    setState(() => _savingCollection = true);
    try {
      await _saveCollection();
    } finally {
      if (mounted) setState(() => _savingCollection = false);
    }
  }

  Future<void> _discardCollection() async {
    if (_savingCollection) return;
    setState(() {
      _pendingCollection = null;
      _collectionError = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_savingCollection,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Açık veresiyeler'),
        actions: [
          IconButton(
            tooltip: 'Ödeme geçmişi / iade',
            icon: const Icon(Icons.history),
            onPressed: _savingCollection || _pendingCollection != null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PaymentHistoryScreen(),
                      ),
                    );
                    if (mounted) await _load();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_savingCollection && _pendingCollection != null)
            const LinearProgressIndicator(),
          if (_pendingCollection != null && !_savingCollection)
            MaterialBanner(
              content: Text(_collectionError ?? 'Tahsilatı kontrol edin.'),
              actions: [
                TextButton(
                  onPressed: _retryCollection,
                  child: const Text('Aynı tahsilatı yeniden dene'),
                ),
                TextButton(
                  onPressed: _discardCollection,
                  child: const Text('Listeyi yenile'),
                ),
              ],
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    ),
  );

  Widget _buildBody() => _loading
      ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
      : _error != null
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Veresiyeler yüklenemedi.'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
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
                  subtitle: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.serviceName ?? 'Hizmet'} • ${DateFormat('dd.MM.yyyy').format(item.appointmentDate)}\n'
                        'Toplam ${_money(item.originalAmountCents)} • Tahsil ${_money(item.collectedCents)}'
                        '${item.refundedCents > 0 ? ' • İade ${_money(item.refundedCents)}' : ''}'
                        '${item.waivedCents > 0 ? ' • Borçtan düşülen ${_money(item.waivedCents)}' : ''}',
                      ),
                      const SizedBox(height: 4),
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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _savingCollection || _pendingCollection != null
                      ? null
                      : () => _collect(item),
                ),
              );
            },
          ),
        );
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
  final _operationId = PaymentTransaction.newOperationId();

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
    final confirmedAt = DateTime.now();
    Navigator.pop(
      context,
      PaymentTransaction(
        appointmentId: widget.item.appointmentId,
        type: PaymentTransactionType.collection,
        amountCents: cents,
        method: _method,
        occurredAt: confirmedAt,
        createdAt: confirmedAt,
        operationId: _operationId,
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
            isExpanded: true,
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Ödeme yöntemi'),
            items: PaymentMethod.values
                .where((method) => method != PaymentMethod.credit)
                .map(
                  (method) => DropdownMenuItem(
                    value: method,
                    child: Text(
                      method.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
