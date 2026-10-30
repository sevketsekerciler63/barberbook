enum CustomerPhotoType { reference, result }

enum CustomerPhotoSource { gallery, camera }

extension CustomerPhotoTypeCodec on CustomerPhotoType {
  String get value => switch (this) {
    CustomerPhotoType.reference => 'reference',
    CustomerPhotoType.result => 'result',
  };

  static CustomerPhotoType fromValue(String? value) => switch (value) {
    'result' => CustomerPhotoType.result,
    _ => CustomerPhotoType.reference,
  };
}

extension CustomerPhotoSourceCodec on CustomerPhotoSource {
  String get value => switch (this) {
    CustomerPhotoSource.gallery => 'gallery',
    CustomerPhotoSource.camera => 'camera',
  };

  static CustomerPhotoSource fromValue(String? value) => switch (value) {
    'camera' => CustomerPhotoSource.camera,
    _ => CustomerPhotoSource.gallery,
  };
}

class CustomerPhoto {
  final int? id;
  final int customerId;
  final String photoPath;
  final CustomerPhotoType type;
  final CustomerPhotoSource source;
  final DateTime createdAt;

  CustomerPhoto({
    this.id,
    required this.customerId,
    required this.photoPath,
    this.type = CustomerPhotoType.reference,
    this.source = CustomerPhotoSource.gallery,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'customerId': customerId,
    'photoPath': photoPath,
    'type': type.value,
    'source': source.value,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CustomerPhoto.fromMap(Map<String, dynamic> map) => CustomerPhoto(
    id: map['id'] as int?,
    customerId: map['customerId'] as int,
    photoPath: map['photoPath'] as String,
    type: CustomerPhotoTypeCodec.fromValue(map['type'] as String?),
    source: CustomerPhotoSourceCodec.fromValue(map['source'] as String?),
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
