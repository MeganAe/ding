class Profile {
  const Profile({
    required this.id,
    required this.firstName,
    this.faculty,
    this.promotion,
  });

  final String id;
  final String firstName;
  final String? faculty;
  final String? promotion;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        firstName: (m['first_name'] as String?) ?? '',
        faculty: m['faculty'] as String?,
        promotion: m['promotion'] as String?,
      );

  String get initial =>
      firstName.isEmpty ? '?' : firstName.substring(0, 1).toUpperCase();

  String get detail => [faculty, promotion]
      .where((e) => e != null && e.isNotEmpty)
      .join(', ');
}

class AlarmItem {
  const AlarmItem({
    required this.id,
    required this.createdAt,
    required this.otherId,
    required this.otherName,
    this.otherFaculty,
  });

  final String id;
  final DateTime createdAt;
  final String otherId;
  final String otherName;
  final String? otherFaculty;

  factory AlarmItem.fromMap(Map<String, dynamic> m) => AlarmItem(
        id: m['alarm_id'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        otherId: m['other_id'] as String,
        otherName: (m['other_name'] as String?) ?? '',
        otherFaculty: m['other_faculty'] as String?,
      );
}
