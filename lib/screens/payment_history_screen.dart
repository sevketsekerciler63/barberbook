import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/payment.dart';
import '../models/payment_account.dart';
import '../models/payment_transaction.dart';
import '../services/database_service.dart';
import '../services/latest_request.dart';
import 'payment_correction_dialog.dart';

class PaymentLedgerGateway {
  const PaymentLedgerGateway();
  Future<List<PaymentAccount>> list(String query) =>
      DatabaseService.instance.getPaymentAccounts(query: query);
  Future<PaymentAccount?> get(int id) =>
      DatabaseService.instance.getPaymentAccount(id);
  Future<int> record(PaymentTransaction request) =>
      DatabaseService.instance.recordPaymentCorrection(request);
}

String _money(int cents) => '${(cents / 100).toStringAsFixed(2)} ₺';
String _date(DateTime value) => DateFormat('dd.MM.yyyy HH:mm').format(value);

class PaymentHistoryScreen extends StatefulWidget {
  final PaymentLedgerGateway ledger;
  const PaymentHistoryScreen({
    super.key,
    this.ledger = const PaymentLedgerGateway(),
  });
  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  final _requests = LatestRequest();
  final _search = TextEditingController();
  List<PaymentAccount> _items = [];
  bool _loading = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requests.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _search.text;
    setState(() {
      _loading = true;
      _failed = false;
    });
    await _requests.run(
      load: () => widget.ledger.list(query),
      apply: (items) {
        if (mounted) {
          setState(() {
            _items = items;
            _loading = false;
          });
        }
      },
      onError: (_, _) {
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ödeme geçmişi')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Müşteri veya randevu no ara',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => _load(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed
              ? Center(
                  child: FilledButton(
                    onPressed: _load,
                    child: const Text('Yeniden dene'),
                  ),
                )
              : _items.isEmpty
              ? const Center(child: Text('Ödeme kaydı bulunamadı.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, index) {
                      final account = _items[index];
                      return ListTile(
                        title: Text(account.customerName),
                        subtitle: Text(
                          '#${account.appointmentId} • ${DateFormat('dd.MM.yyyy').format(account.appointmentDate)}\n'
                          'İlk hizmet ${_money(account.payment.amountCents)} • Kalan borç ${_money(account.outstandingCents)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PaymentAccountScreen(
                                appointmentId: account.appointmentId,
                                ledger: widget.ledger,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class PaymentAccountScreen extends StatefulWidget {
  final int appointmentId;
  final PaymentLedgerGateway ledger;
  const PaymentAccountScreen({
    super.key,
    required this.appointmentId,
    this.ledger = const PaymentLedgerGateway(),
  });
  @override
  State<PaymentAccountScreen> createState() => _PaymentAccountScreenState();
}

class _PaymentAccountScreenState extends State<PaymentAccountScreen> {
  PaymentAccount? _account;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  PaymentTransaction? _pending;
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
      _account = null;
    });
    try {
      final account = await widget.ledger.get(widget.appointmentId);
      if (mounted) {
        setState(() {
          _account = account;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Ödeme geçmişi yüklenemedi.';
        });
      }
    }
  }

  Future<void> _start(PaymentTransactionType type) async {
    if (_busy || _pending != null || _account == null) return;
    setState(() => _busy = true);
    try {
      final request = await showPaymentCorrectionDialog(
        context,
        _account!,
        type,
      );
      if (request == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            type == PaymentTransactionType.refund
                ? 'Para iadesini kaydet'
                : 'Borçtan düşmeyi kaydet',
          ),
          content: Text(
            '${_money(request.amountCents)}\nHizmet: ${_money(request.serviceCents)} • Bahşiş: ${_money(request.tipCents)}\n'
            '${type == PaymentTransactionType.refund ? request.method.label : 'Para hareketi yok'}\nGerekçe: ${request.note}\n\nEski kayıt korunur; yeni hareket bugüne kaydedilir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Onayla ve kaydet'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final confirmedAt = DateTime.now();
      _pending = PaymentTransaction(
        appointmentId: request.appointmentId,
        type: request.type,
        amountCents: request.amountCents,
        tipCents: request.tipCents,
        method: request.method,
        note: request.note,
        operationId: request.operationId,
        occurredAt: confirmedAt,
        createdAt: confirmedAt,
      );
      await _save();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final request = _pending;
    if (request == null) return;
    try {
      await widget.ledger.record(request);
      _pending = null;
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Düzeltme hareketi kaydedildi.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'İşlem tamamlanamadı. Aynı işlemle yeniden deneyin veya geçmişi yenileyin.',
        );
      }
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _save();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverse(PaymentTransaction original) async {
    if (_busy || _pending != null) return;
    if (original.type == PaymentTransactionType.collection &&
        original.amountCents > (_account?.refundableServiceCents ?? 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu tahsilatın bir kısmı iade edilmiş. Önce ilgili iadeyi geri alın.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final request = await showPaymentReversalDialog(context, original);
      if (request == null || !mounted) return;
      _pending = request;
      await _save();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardAndReload() async {
    _pending = null;
    await _load();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Ödeme hareketleri')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!),
                  if (_pending != null)
                    FilledButton(
                      onPressed: _busy ? null : _retry,
                      child: const Text('Aynı işlemi yeniden dene'),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _discardAndReload,
                    child: const Text('Geçmişi yenile'),
                  ),
                ],
                if (_account == null && _error == null)
                  const Text('Ödeme kaydı bulunamadı.'),
                if (_account case final account?) ...[
                  Text(
                    account.customerName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '#${account.appointmentId} • ${account.serviceName ?? 'Hizmet'}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'İlk hizmet: ${_money(account.payment.amountCents)}\nİlk indirim: ${_money(account.payment.discountCents)}\nİlk bahşiş: ${_money(account.payment.tipCents)}\n'
                    'Kalan hizmet iadesi: ${_money(account.refundableServiceCents)}\nKalan bahşiş iadesi: ${_money(account.refundableTipCents)}\n'
                    'İade edilen hizmet: ${_money(account.refundedServiceCents)}\nBorçtan düşülen: ${_money(account.waivedCents)}\nKalan veresiye: ${_money(account.outstandingCents)}',
                  ),
                  const SizedBox(height: 12),
                  if (account.supportsCorrections)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed:
                              _busy ||
                                  _pending != null ||
                                  account.refundableServiceCents +
                                          account.refundableTipCents ==
                                      0
                              ? null
                              : () => _start(PaymentTransactionType.refund),
                          child: const Text('Para iadesi'),
                        ),
                        OutlinedButton(
                          onPressed:
                              _busy ||
                                  _pending != null ||
                                  account.outstandingCents == 0
                              ? null
                              : () => _start(PaymentTransactionType.adjustment),
                          child: const Text('Borçtan düş'),
                        ),
                      ],
                    ),
                  const Divider(height: 32),
                  const Text(
                    'İlk kayıt (değiştirilmez)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_date(account.payment.createdAt)} • ${account.payment.method.label}\n'
                    '${account.payment.status == PaymentStatus.pending
                        ? 'Veresiye'
                        : account.payment.status == PaymentStatus.paid
                        ? 'Tahsilat'
                        : 'Eski / bilinmeyen durum'} • ${account.payment.note ?? ''}',
                  ),
                  const SizedBox(height: 16),
                  for (final movement in account.transactions)
                    Card(
                      child: ListTile(
                        trailing:
                            movement.id != null &&
                                movement.reversesTransactionId == null &&
                                !account.transactions.any(
                                  (t) => t.reversesTransactionId == movement.id,
                                )
                            ? IconButton(
                                tooltip:
                                    movement.type ==
                                        PaymentTransactionType.collection
                                    ? 'Tahsilatı geri al'
                                    : 'Bu düzeltmeyi geri al',
                                icon: const Icon(Icons.undo),
                                onPressed: _busy || _pending != null
                                    ? null
                                    : () => _reverse(movement),
                              )
                            : null,
                        title: Text(
                          '${movement.reversesTransactionId != null ? 'Geri alma • ' : ''}${switch (movement.type) {
                            PaymentTransactionType.collection => 'Tahsilat',
                            PaymentTransactionType.refund => 'Para iadesi',
                            PaymentTransactionType.adjustment => 'Borçtan düşme',
                          }} • ${_money(movement.amountCents)}',
                        ),
                        subtitle: Text(
                          '${_date(movement.occurredAt)} • ${movement.type == PaymentTransactionType.adjustment ? 'Para hareketi yok' : movement.method.label}\n'
                          '${movement.tipCents > 0 ? 'Bahşiş iadesi ${_money(movement.tipCents)}\n' : ''}${movement.note ?? ''}',
                        ),
                      ),
                    ),
                ],
              ],
            ),
    ),
  );
}
