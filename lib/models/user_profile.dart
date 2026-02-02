class UserProfile {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String? college; // This is the collegeId string
  final String? collegeId; // Alias for college
  final String? createdOn; // ISO string format
  final bool? active;
  final String? status;
  final String? phone;
  final String? phoneNumber;
  final String? designation;
  final String? district;
  final DateTime? updatedAt;
  final bool? profileCompleted;
  final String? photoUrl;
  final String? employmentType;
  final String? payBand;
  final DateTime? dateOfAppointment;
  final DateTime? dateOfBirth;
  final DateTime? dateOfConfirmation;
  final DateTime? dateOfRetirement;
  final bool? govtQuarter;

  UserProfile({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.college,
    this.collegeId,
    this.createdOn,
    this.active,
    this.status,
    this.phone,
    this.phoneNumber,
    this.designation,
    this.district,
    this.updatedAt,
    this.profileCompleted,
    this.photoUrl,
    this.employmentType,
    this.payBand,
    this.dateOfAppointment,
    this.dateOfBirth,
    this.dateOfConfirmation,
    this.dateOfRetirement,
    this.govtQuarter,
  });

  factory UserProfile.fromFirestore(Map<String, dynamic> data, String id) {
    // Parse dates - handle both Timestamp and string formats
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return null;
        }
      }
      // Handle Firestore Timestamp
      if (value.toString().contains('Timestamp')) {
        try {
          return (value as dynamic).toDate();
        } catch (e) {
          return null;
        }
      }
      return null;
    }

    final collegeId = data['college'] ?? data['collegeId'];
    
    return UserProfile(
      uid: id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? '',
      college: collegeId,
      collegeId: collegeId, // Use college field as collegeId
      createdOn: data['createdOn']?.toString(),
      active: data['active'],
      status: data['status'],
      phone: data['phone'],
      phoneNumber: data['phoneNumber'],
      designation: data['designation'],
      district: data['district'],
      updatedAt: parseDate(data['updatedAt']),
      profileCompleted: data['profileCompleted'],
      photoUrl: data['photoUrl'],
      employmentType: data['employmentType'],
      payBand: data['payBand'],
      dateOfAppointment: parseDate(data['dateOfAppointment']),
      dateOfBirth: parseDate(data['dateOfBirth']),
      dateOfConfirmation: parseDate(data['dateOfConfirmation']),
      dateOfRetirement: parseDate(data['dateOfRetirement']),
      govtQuarter: data['govtQuarter'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'role': role,
      if (college != null) 'college': college,
      if (collegeId != null) 'collegeId': collegeId,
      if (createdOn != null) 'createdOn': createdOn,
      if (active != null) 'active': active,
      if (status != null) 'status': status,
      if (phone != null) 'phone': phone,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (designation != null) 'designation': designation,
      if (district != null) 'district': district,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (profileCompleted != null) 'profileCompleted': profileCompleted,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (employmentType != null) 'employmentType': employmentType,
      if (payBand != null) 'payBand': payBand,
      if (dateOfAppointment != null) 'dateOfAppointment': dateOfAppointment,
      if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
      if (dateOfConfirmation != null) 'dateOfConfirmation': dateOfConfirmation,
      if (dateOfRetirement != null) 'dateOfRetirement': dateOfRetirement,
      if (govtQuarter != null) 'govtQuarter': govtQuarter,
    };
  }
}
