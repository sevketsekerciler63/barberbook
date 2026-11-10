import 'dart:async';

/// Holds ringing episodes until an authorized Home screen has a navigator.
/// A callback must check [isCurrent] immediately before presenting its UI.
class AlarmDeliveryGate {
  final Future<bool> Function(int id, bool Function() isCurrent) deliver;
  final Map<int, Object> _episodes = {};
  final Set<int> _handled = {};
  final Set<int> _cancelled = {};
  bool _ready = false;
  int _changes = 0;
  int _readinessVersion = 0;
  Future<void>? _running;

  AlarmDeliveryGate({required this.deliver});

  Future<void> updateRinging(Set<int> ids) {
    _episodes.removeWhere((id, _) => !ids.contains(id));
    _handled.removeWhere((id) => !ids.contains(id));
    _cancelled.retainAll(ids);
    for (final id in ids) {
      if (!_cancelled.contains(id)) _episodes.putIfAbsent(id, Object.new);
    }
    _changes++;
    return _startDrain();
  }

  Future<void> setReady(bool ready) {
    if (_ready != ready) {
      _readinessVersion++;
      _changes++;
      _ready = ready;
    }
    return _startDrain();
  }

  void cancel(int id) {
    if (_episodes.remove(id) != null) _cancelled.add(id);
    _handled.remove(id);
    _changes++;
  }

  void clear() {
    _cancelled.addAll(_episodes.keys);
    _episodes.clear();
    _handled.clear();
    _changes++;
  }

  Future<void> _startDrain() {
    final running = _running;
    if (running != null) return running;
    if (!_ready) return Future.value();
    final completion = Completer<void>();
    _running = completion.future;
    _drain().then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<void> _drain() async {
    try {
      int revision;
      do {
        revision = _changes;
        final pending = _episodes.entries
            .where((entry) => !_handled.contains(entry.key))
            .toList();
        for (final entry in pending) {
          if (!_ready) break;
          final readiness = _readinessVersion;
          bool isCurrent() =>
              _ready &&
              readiness == _readinessVersion &&
              identical(_episodes[entry.key], entry.value);
          if (!isCurrent()) continue;
          try {
            final delivered = await deliver(entry.key, isCurrent);
            if (delivered && isCurrent()) _handled.add(entry.key);
          } catch (_) {
            // Keep this episode pending for a later ready/ringing update.
            // A failing database read must not escape the native stream listener.
          }
        }
      } while (_ready && revision != _changes);
    } finally {
      _running = null;
    }
  }
}
