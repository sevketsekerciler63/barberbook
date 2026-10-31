import 'dart:async';
import 'package:berber_randevu/services/serial_task_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native read-and-set operations cannot overlap', () async {
    final queue = SerialTaskQueue();
    final gate = Completer<void>();
    final events = <int>[];
    final first = queue.run(() async {
      events.add(1);
      await gate.future;
      events.add(2);
    });
    final second = queue.run(() async {
      events.add(3);
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, [1]);
    gate.complete();
    await Future.wait([first, second]);
    expect(events, [1, 2, 3]);
  });
  test('a failed native operation does not poison later scheduling', () async {
    final queue = SerialTaskQueue();
    await expectLater(
      queue.run(() async => throw StateError('native failure')),
      throwsStateError,
    );
    expect(await queue.run(() async => 42), 42);
  });
}
