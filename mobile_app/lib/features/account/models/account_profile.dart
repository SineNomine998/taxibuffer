class AccountProfile {
  final String firstName;
  final String lastName;
  final String email;
  final String taxiLicenseNumber;
  final String tto;
  final String phoneNumber;

  const AccountProfile({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.taxiLicenseNumber,
    required this.tto,
    required this.phoneNumber,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    return AccountProfile(
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      taxiLicenseNumber: json['taxi_license_number']?.toString() ?? '',
      tto: json['tto']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'taxi_license_number': taxiLicenseNumber,
      'tto': tto,
      'phone_number': phoneNumber,
    };
  }
}
