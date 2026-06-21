class Vehicle {
  final int? id;
  final String nickname;
  final String licensePlate;
  final String vehicleType; // 'auto' | 'busje'
  final bool isCurrent;

  const Vehicle({
    this.id,
    required this.nickname,
    required this.licensePlate,
    required this.vehicleType,
    this.isCurrent = false,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
    id: json['id'] as int?,
    nickname: json['nickname'] as String,
    licensePlate: json['license_plate'] as String,
    vehicleType: json['vehicle_type'] as String,
    isCurrent: json['is_current'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'nickname': nickname,
    'license_plate': licensePlate,
    'vehicle_type': vehicleType,
    'is_current': isCurrent,
  };
}
