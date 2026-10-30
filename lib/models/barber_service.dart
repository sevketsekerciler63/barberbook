BarberService? selectServiceForAppointment(
  List<BarberService> services,
  int? appointmentServiceId,
) {
  if (appointmentServiceId != null) {
    for (final service in services) {
      if (service.id == appointmentServiceId) return service;
    }
  }
  for (final service in services) {
    if (service.isActive) return service;
  }
  return null;
}

class BarberService {
  final int? id;
  final String name;
  final int durationMinutes;
  final int? priceCents;
  final bool isActive;

  BarberService({
    this.id,
    required this.name,
    required this.durationMinutes,
    this.priceCents,
    this.isActive = true,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Hizmet adı boş olamaz.');
    }
    if (durationMinutes <= 0) {
      throw ArgumentError.value(
        durationMinutes,
        'durationMinutes',
        'Hizmet süresi pozitif olmalıdır.',
      );
    }
    if (priceCents != null && priceCents! < 0) {
      throw ArgumentError.value(
        priceCents,
        'priceCents',
        'Hizmet fiyatı negatif olamaz.',
      );
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name.trim(),
    'durationMinutes': durationMinutes,
    'priceCents': priceCents,
    'isActive': isActive ? 1 : 0,
  };

  factory BarberService.fromMap(Map<String, dynamic> map) => BarberService(
    id: map['id'] as int?,
    name: map['name'] as String,
    durationMinutes: (map['durationMinutes'] as int?) ?? 30,
    priceCents: map['priceCents'] as int?,
    isActive: (map['isActive'] as int?) != 0,
  );

  BarberService copyWith({
    int? id,
    String? name,
    int? durationMinutes,
    int? priceCents,
    bool clearPrice = false,
    bool? isActive,
  }) => BarberService(
    id: id ?? this.id,
    name: name ?? this.name,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    priceCents: clearPrice ? null : priceCents ?? this.priceCents,
    isActive: isActive ?? this.isActive,
  );
}
