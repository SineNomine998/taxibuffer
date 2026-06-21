class PickupZone {
  final int queueId;
  final String name;
  final String? address;
  final String? imageUrl;
  final bool isActive;

  const PickupZone({
    required this.queueId,
    required this.name,
    this.address,
    this.imageUrl,
    required this.isActive,
  });

  factory PickupZone.fromJson(Map<String, dynamic> json) {
    return PickupZone(
      queueId: json['queue_id'] as int,
      name: json['name'] as String,
      address: json['address'] as String?,
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}
