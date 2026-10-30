import 'package:berber_randevu/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decimal amounts are parsed exactly in cents', () {
    expect(parseMoneyCents('123,45'), 12345);
    expect(parseMoneyCents(' 0.29 '), 29);
    expect(parseMoneyCents('12,5'), 1250);
    expect(parseMoneyCents('10'), 1000);
    expect(parseMoneyCents(''), 0);
    expect(parseMoneyCents('', emptyAsZero: false), isNull);
  });
  test('non-finite, negative, grouping and extra precision are rejected', () {
    for (final input in [
      'NaN',
      'Infinity',
      '-1',
      '1e3',
      '1,234',
      '1.000,00',
      '10000000000',
    ]) {
      expect(parseMoneyCents(input), isNull, reason: input);
    }
  });
}
