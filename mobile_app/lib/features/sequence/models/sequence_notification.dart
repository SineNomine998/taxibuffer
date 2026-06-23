class SequenceNotification {
  final int id;
  final int sequenceNumber;
  final String response;
  final String queueName;
  final String localTime;

  const SequenceNotification({
    required this.id,
    required this.sequenceNumber,
    required this.response,
    required this.queueName,
    required this.localTime,
  });

  factory SequenceNotification.fromJson(Map<String, dynamic> json) {
    return SequenceNotification(
      id: json['id'] as int,
      sequenceNumber: json['sequence_number'] as int,
      response: json['response'] as String? ?? '',
      queueName: json['queue_name'] as String? ?? '',
      localTime: json['local_time'] as String? ?? '',
    );
  }
}
