class Customer {
  static const int maxNotesLength = 500;

  final int? id;
  final String name;
  final String? phone;
  final String? notes;
  final String? favoriteHairstyle;
  final String? photoPath;
  final int totalAppointments;
  final DateTime? lastAppointmentDate;
  final DateTime createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.notes,
    this.favoriteHairstyle,
    this.photoPath,
    this.totalAppointments = 0,
    this.lastAppointmentDate,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'notes': notes,
      'favoriteHairstyle': favoriteHairstyle,
      'photoPath': photoPath,
      'totalAppointments': totalAppointments,
      'lastAppointmentDate': lastAppointmentDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      notes: map['notes'] as String?,
      favoriteHairstyle: map['favoriteHairstyle'] as String?,
      photoPath: map['photoPath'] as String?,
      totalAppointments: map['totalAppointments'] as int? ?? 0,
      lastAppointmentDate: map['lastAppointmentDate'] != null
          ? DateTime.parse(map['lastAppointmentDate'] as String)
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? notes,
    String? favoriteHairstyle,
    String? photoPath,
    bool clearPhotoPath = false,
    int? totalAppointments,
    DateTime? lastAppointmentDate,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      favoriteHairstyle: favoriteHairstyle ?? this.favoriteHairstyle,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
      totalAppointments: totalAppointments ?? this.totalAppointments,
      lastAppointmentDate: lastAppointmentDate ?? this.lastAppointmentDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
