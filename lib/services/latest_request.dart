/// Keeps a slow response from replacing newer results or a disposed screen.
class LatestRequest {
  int _revision = 0;
  bool _disposed = false;
  void invalidate() => _revision++;
  void dispose() {
    _disposed = true;
    invalidate();
  }

  Future<void> run<T>({
    required Future<T> Function() load,
    required void Function(T) apply,
    required void Function(Object, StackTrace) onError,
  }) async {
    final revision = ++_revision;
    try {
      final value = await load();
      if (!_disposed && revision == _revision) apply(value);
    } catch (error, stack) {
      if (!_disposed && revision == _revision) onError(error, stack);
    }
  }
}
