/// Serializes native mutations; a failed task does not block the next request.
class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();
  Future<T> run<T>(Future<T> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
