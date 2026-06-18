class Vehicle {
  final String nickname;
  final String licensePlate;
  final String vehicleType; // 'auto' | 'busje'
  final bool isCurrent;

  const Vehicle({
    required this.nickname,
    required this.licensePlate,
    required this.vehicleType,
    this.isCurrent = false,
  });

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'license_plate': licensePlate,
    'vehicle_type': vehicleType,
    'is_current': isCurrent,
  };
}
