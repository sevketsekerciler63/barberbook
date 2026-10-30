import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';

import '../models/cash_report.dart';
import '../models/payment.dart';
import '../services/cash_report_csv.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';
import 'receivables_screen.dart';

class CashReportScreen extends StatefulWidget {
  const CashReportScreen({super.key});

  @override
  State<CashReportScreen> createState() => _CashReportScreenState();
}

class _CashReportScreenState extends State<CashReportScreen> {
  late DateTime _start;
  late DateTime _end;
  CashReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = _start;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await DatabaseService.instance.getCashReport(_start, _end);
      if (!mounted) return;
      setState(() {
        _report = report;
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

  void _selectPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      switch (preset) {
        case 'week':
          _start = today.subtract(Duration(days: today.weekday - 1));
          _end = today;
        case 'month':
          _start = DateTime(today.year, today.month, 1);
          _end = today;
        default:
          _start = today;
          _end = today;
      }
    });
    _load();
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (range == null) return;
    setState(() {
      _start = range.start;
      _end = range.end;
    });
    await _load();
  }

  String _money(int cents) => '${(cents / 100).toStringAsFixed(2)} ₺';

  Future<void> _exportCsv() async {
    final report = _report;
    if (report == null) return;
    try {
      final directory = Directory(p.join(await getDatabasesPath(), 'reports'));
      await directory.create(recursive: true);
      final date = DateFormat('yyyyMMdd');
      final file = File(
        p.join(
          directory.path,
          'kasa_${date.format(_start)}_${date.format(_end)}.csv',
        ),
      );
      await file.writeAsString(
        '\uFEFF${CashReportCsv.build(report, _start, _end)}',
        flush: true,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'BarberBook kasa raporu',
          text:
              '${DateFormat('dd.MM.yyyy').format(_start)} – '
              '${DateFormat('dd.MM.yyyy').format(_end)} tahsilat raporu',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV raporu oluşturuldu: ${file.path}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV oluşturulamadı: $error')));
      }
    }
  }

  Widget _metric(String label, int cents, IconData icon) {
    return Expanded(
      child: Card(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon, color: AppColors.gold),
              const SizedBox(height: 8),
              Text(
                _money(cents),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd.MM.yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tahsilat raporu'),
        actions: [
          IconButton(
            tooltip: 'Açık veresiyeler',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceivablesScreen()),
              );
              if (mounted) await _load();
            },
          ),
          IconButton(
            tooltip: 'CSV oluştur',
            onPressed: _report == null ? null : _exportCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Bugün'),
                  onPressed: () => _selectPreset('today'),
                ),
                ActionChip(
                  label: const Text('Bu hafta'),
                  onPressed: () => _selectPreset('week'),
                ),
                ActionChip(
                  label: const Text('Bu ay'),
                  onPressed: () => _selectPreset('month'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text('${date.format(_start)} – ${date.format(_end)}'),
                  onPressed: _pickRange,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  )
                : _error != null
                ? Center(
                    child: FilledButton(
                      onPressed: _load,
                      child: const Text('Tekrar dene'),
                    ),
                  )
                : _buildReport(_report!),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(CashReport report) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              _metric(
                'Hizmet tahsilatı',
                report.collectedCents,
                Icons.payments_outlined,
              ),
              _metric('İndirim', report.discountCents, Icons.discount_outlined),
            ],
          ),
          Row(
            children: [
              _metric(
                'Bahşiş',
                report.tipCents,
                Icons.volunteer_activism_outlined,
              ),
              _metric(
                'Güncel açık veresiye',
                report.outstandingCents,
                Icons.account_balance_wallet_outlined,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Bahşiş hizmet tahsilatından ayrı gösterilir. Açık veresiye, seçilen tarih aralığından bağımsız güncel bakiyedir.',
            ),
          ),
          Card(
            color: AppColors.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ödeme yöntemleri • ${report.collectionCount} tahsilat',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  if (report.byMethod.isEmpty)
                    const Text('Bu aralıkta tahsilat bulunmuyor.')
                  else
                    for (final method in PaymentMethod.values)
                      if (report.byMethod[method] != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(method.label),
                          trailing: Text(_money(report.byMethod[method]!)),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
