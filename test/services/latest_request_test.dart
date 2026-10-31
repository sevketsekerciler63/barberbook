import 'dart:async';
import 'package:berber_randevu/services/latest_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slow old search cannot replace a newer completed query', () async {
    final request = LatestRequest();
    final old = Completer<String>();
    final latest = Completer<String>();
    final results = <String>[];
    final first = request.run(
      load: () => old.future,
      apply: results.add,
      onError: (_, _) => fail('unexpected error'),
    );
    final second = request.run(
      load: () => latest.future,
      apply: results.add,
      onError: (_, _) => fail('unexpected error'),
    );
    latest.complete('new');
    await second;
    old.complete('old');
    await first;
    expect(results, ['new']);
  });
  test('clearing a query invalidates its in-flight response', () async {
    final request = LatestRequest();
    final pending = Completer<String>();
    final values = <String>[];
    final job = request.run(
      load: () => pending.future,
      apply: values.add,
      onError: (_, _) => fail('unexpected error'),
    );
    request.invalidate();
    pending.complete('obsolete');
    await job;
    expect(values, isEmpty);
  });
  test('disposed view ignores late results and errors', () async {
    final request = LatestRequest();
    final pending = Completer<String>();
    var callbacks = 0;
    final job = request.run(
      load: () => pending.future,
      apply: (_) => callbacks++,
      onError: (_, _) => callbacks++,
    );
    request.dispose();
    pending.completeError(StateError('late'));
    await job;
    expect(callbacks, 0);
  });
  test(
    'new request failure cannot let an older success masquerade as current data',
    () async {
      final request = LatestRequest();
      final old = Completer<String>();
      final latest = Completer<String>();
      final values = <String>[];
      final first = request.run(
        load: () => old.future,
        apply: values.add,
        onError: (_, _) => values.add('old error'),
      );
      final second = request.run(
        load: () => latest.future,
        apply: values.add,
        onError: (_, _) => values.add('new error'),
      );
      latest.completeError(StateError('disk'));
      await second;
      old.complete('obsolete');
      await first;
      expect(values, ['new error']);
    },
  );
}
