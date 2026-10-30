/// Parses a non-negative amount without floating-point rounding or grouping.
/// Both Turkish decimal commas and decimal points are accepted.
int? parseMoneyCents(String text, {bool emptyAsZero = true}) {
  final value = text.trim();
  if (value.isEmpty) return emptyAsZero ? 0 : null;
  if (!RegExp(r'^\d{1,10}([.,]\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.replaceAll(',', '.').split('.');
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  return int.parse(parts.first) * 100 + fraction;
}
