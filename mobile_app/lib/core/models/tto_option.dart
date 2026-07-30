class TtoOption {
  final String value;
  final String label;

  const TtoOption({required this.value, required this.label});

  factory TtoOption.fromJson(Map<String, dynamic> json) {
    return TtoOption(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }
}
