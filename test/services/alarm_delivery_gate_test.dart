import 'dart:async';
import 'package:berber_randevu/services/alarm_delivery_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'only current ringing episodes are delivered once after Home is ready',
    () async {
      final delivered = <int>[];
      final gate = AlarmDeliveryGate(
        deliver: (id, current) async {
          expect(current(), isTrue);
          delivered.add(id);
          return true;
        },
      );
      await gate.updateRinging({1, 2});
      await gate.updateRinging({2});
      expect(delivered, isEmpty);
      await gate.setReady(true);
      await gate.updateRinging({2});
      expect(delivered, [2]);
      await gate.updateRinging({});
      await gate.updateRinging({2});
      expect(delivered, [2, 2]);
    },
  );

  test('cancelled alarm cannot reenter from a stale native snapshot', () async {
    final delivered = <int>[];
    final gate = AlarmDeliveryGate(
      deliver: (id, _) async {
        delivered.add(id);
        return true;
      },
    );
    await gate.updateRinging({1});
    gate.cancel(1);
    await gate.updateRinging({1, 2});
    await gate.setReady(true);
    expect(delivered, [2]);
    await gate.updateRinging({2});
    await gate.updateRinging({1, 2});
    expect(delivered, [2, 1]);
  });

  test('closing Home invalidates delivery during an async read', () async {
    final pending = Completer<void>();
    final delivered = <int>[];
    final gate = AlarmDeliveryGate(
      deliver: (id, current) async {
        await pending.future;
        if (!current()) return false;
        delivered.add(id);
        return true;
      },
    );
    await gate.updateRinging({1});
    final opening = gate.setReady(true);
    final closing = gate.setReady(false);
    pending.complete();
    await Future.wait([opening, closing]);
    expect(delivered, isEmpty);
    await gate.setReady(true);
    expect(delivered, [1]);
  });
}
