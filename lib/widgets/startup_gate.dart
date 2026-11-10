import 'package:flutter/material.dart';

import '../services/startup_service.dart';
import '../utils/constants.dart';

/// The loading/error shell exists before any fallible platform initialization.
/// Only a completed startup can construct the application's data screens.
class StartupGate extends StatefulWidget {
  final StartupGateway gateway;
  final Widget Function(BuildContext context, bool accessAllowed) readyBuilder;

  const StartupGate({
    super.key,
    this.gateway = const StartupGateway(),
    required this.readyBuilder,
  });

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final StartupSequence _sequence;
  StartupStage _stage = StartupStage.platform;
  bool _busy = false;
  bool _failed = false;
  bool? _accessAllowed;

  @override
  void initState() {
    super.initState();
    _sequence = StartupSequence(widget.gateway);
    _start();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final allowed = await _sequence.run(
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (mounted) setState(() => _accessAllowed = allowed);
    } catch (_) {
      // Raw native/database exceptions may include private paths or records.
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _accessAllowed;
    if (allowed != null) return widget.readyBuilder(context, allowed);
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.gold,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.content_cut, size: 40),
                  const SizedBox(height: 16),
                  const Text('BarberBook', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 24),
                  if (_failed) ...[
                    const Text(
                      'Uygulama hazırlanamadı.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(_stage.label, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text(
                      'Mevcut kayıtları silmeden yeniden deneyebilirsiniz.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Yeniden dene'),
                    ),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_stage.label, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
