class ActivityLogItem {
  final int id;
  final String eventType;
  final String title;
  final String message;
  final String? queueName;
  final int? queuePosition;
  final int? previousQueuePosition;
  final int? sequenceNumber;
  final String localDate;
  final String localTime;

  const ActivityLogItem({
    required this.id,
    required this.eventType,
    required this.title,
    required this.message,
    required this.queueName,
    required this.queuePosition,
    required this.previousQueuePosition,
    required this.sequenceNumber,
    required this.localDate,
    required this.localTime,
  });

  factory ActivityLogItem.fromJson(Map<String, dynamic> json) {
    return ActivityLogItem(
      id: json['id'] as int,
      eventType: json['event_type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      queueName: json['queue_name']?.toString(),
      queuePosition: json['queue_position'] as int?,
      previousQueuePosition: json['previous_queue_position'] as int?,
      sequenceNumber: json['sequence_number'] as int?,
      localDate: json['local_date']?.toString() ?? '',
      localTime: json['local_time']?.toString() ?? '',
    );
  }
}
