class WaitingPerson {
  final int position;
  final String firstName;
  final String licensePlate;
  final bool isCurrentChauffeur;

  const WaitingPerson({
    required this.position,
    required this.firstName,
    required this.licensePlate,
    required this.isCurrentChauffeur,
  });

  factory WaitingPerson.fromJson(Map<String, dynamic> json) => WaitingPerson(
    position: json['position'] as int? ?? 0,
    firstName: json['first_name'] as String? ?? 'Onbekend',
    licensePlate: json['license_plate'] as String? ?? '-',
    isCurrentChauffeur: json['is_current_chauffeur'] as bool? ?? false,
  );
}

class QueueNotification {
  final int id;
  final int? sequenceNumber;

  const QueueNotification({required this.id, this.sequenceNumber});

  factory QueueNotification.fromJson(Map<String, dynamic> json) =>
      QueueNotification(
        id: json['id'] as int,
        sequenceNumber: json['sequence_number'] as int?,
      );
}

class QueueStatus {
  final bool active;
  final int? position;
  final String queueName;
  final String? queueAddress;
  final String? imageUrl;
  final List<WaitingPerson> waitingPeople;
  final bool hasNotification;
  final QueueNotification? notification;

  const QueueStatus({
    required this.active,
    this.position,
    required this.queueName,
    this.queueAddress,
    this.imageUrl,
    required this.waitingPeople,
    required this.hasNotification,
    this.notification,
  });

  factory QueueStatus.fromJson(Map<String, dynamic> json) => QueueStatus(
    active: json['active'] as bool? ?? false,
    position: json['position'] as int?,
    queueName: json['queue_name'] as String? ?? '',
    queueAddress: json['queue_address'] as String?,
    imageUrl: json['image_url'] as String?,
    waitingPeople: (json['waiting_people'] as List? ?? [])
        .map((e) => WaitingPerson.fromJson(e as Map<String, dynamic>))
        .toList(),
    hasNotification: json['has_notification'] as bool? ?? false,
    notification: json['notification'] != null
        ? QueueNotification.fromJson(
            json['notification'] as Map<String, dynamic>,
          )
        : null,
  );
}
