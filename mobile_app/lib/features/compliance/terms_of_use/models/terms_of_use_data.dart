class TermsOfUseData {
  final String version;
  final String title;
  final String bodyNl;
  final String effectiveFrom;
  final bool accepted;

  const TermsOfUseData({
    required this.version,
    required this.title,
    required this.bodyNl,
    required this.effectiveFrom,
    required this.accepted,
  });

  factory TermsOfUseData.fromJson(Map<String, dynamic> json) {
    return TermsOfUseData(
      version: json['version']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Gebruiksvoorwaarden',
      bodyNl: json['body_nl']?.toString() ?? '',
      effectiveFrom: json['effective_from']?.toString() ?? '',
      accepted: json['accepted'] == true,
    );
  }
}
