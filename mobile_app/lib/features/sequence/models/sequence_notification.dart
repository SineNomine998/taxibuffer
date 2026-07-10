class SequenceNotification {
  final int id;
  final int sequenceNumber;
  final String response;
  final String entryStatus;
  final String queueName;
  final String localTime;

  const SequenceNotification({
    required this.id,
    required this.sequenceNumber,
    required this.response,
    required this.entryStatus,
    required this.queueName,
    required this.localTime,
  });

  factory SequenceNotification.fromJson(Map<String, dynamic> json) {
    return SequenceNotification(
      id: json['id'] as int? ?? 0,
      sequenceNumber: json['sequence_number'] as int? ?? 0,
      response: json['response']?.toString() ?? '',
      entryStatus: json['entry_status']?.toString() ?? '',
      queueName: json['queue_name']?.toString() ?? 'Onbekende wachtrij',
      localTime: json['local_time']?.toString() ?? '--:--',
    );
  }

  bool get isActiveCall => entryStatus == 'notified';
  bool get isHandled => entryStatus == 'dequeued';
}
