class AccountProfile {
  final String firstName;
  final String lastName;
  final String email;
  final String taxiLicenseNumber;

  const AccountProfile({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.taxiLicenseNumber,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    return AccountProfile(
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      email: json['email'] as String? ?? '',
      taxiLicenseNumber: json['taxi_license_number'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'first_name': firstName,
    'last_name': lastName,
    'email': email,
    'taxi_license_number': taxiLicenseNumber,
  };
}
