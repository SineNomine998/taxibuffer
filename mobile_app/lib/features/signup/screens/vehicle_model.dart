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
}
