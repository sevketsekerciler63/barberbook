import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/backup_file_gateway.dart';
import '../services/backup_recency.dart';
import '../services/latest_request.dart';

class BackupSummary extends StatelessWidget {
  final BackupRecency status;
  final VoidCallback? onOpen;
  const BackupSummary({super.key, required this.status, this.onOpen});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.title, style: Theme.of(context).textTheme.titleMedium),
          if (status.latest != null)
            Text(DateFormat('dd.MM.yyyy HH:mm').format(status.latest!)),
          const SizedBox(height: 8),
          Text(switch (status.kind) {
            BackupRecencyKind.unavailable =>
              'Yedek dosyalarını kontrol edip yeniden deneyin.',
            BackupRecencyKind.futureDate =>
              'Cihaz saatini ve yedek dosyasının tarihini kontrol edin.',
            _ => 'Yedeğinizin bir kopyasını cihaz dışına da kaydedin.',
          }),
          if (onOpen != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Yedeklemeyi aç'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Refreshes on return from backup management, app resume, and hourly while
/// visible. It does not schedule OS notifications or create/share any files.
class BackupReminder extends StatefulWidget {
  final BackupFileGateway files;
  final Future<void> Function() onOpen;
  final int revision;
  final DateTime Function()? now;
  const BackupReminder({
    super.key,
    this.files = const BackupFileGateway(),
    required this.onOpen,
    this.revision = 0,
    this.now,
  });

  @override
  State<BackupReminder> createState() => _BackupReminderState();
}

class _BackupReminderState extends State<BackupReminder>
    with WidgetsBindingObserver {
  final _request = LatestRequest();
  BackupRecency? _status;
  Timer? _timer;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(hours: 1), (_) {
      if ((WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant BackupReminder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.files != widget.files) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() => _request.run(
    load: widget.files.list,
    apply: (entries) => setState(() {
      _status = BackupRecency.fromEntries(
        entries,
        now: widget.now?.call() ?? DateTime.now(),
      );
    }),
    onError: (_, _) =>
        setState(() => _status = const BackupRecency.unavailable()),
  );

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpen();
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        await _load();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _request.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || !status.needsAttention) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: BackupSummary(status: status, onOpen: _opening ? null : _open),
    );
  }
}
