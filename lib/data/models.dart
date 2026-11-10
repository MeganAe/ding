String? _str(dynamic v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

class Profile {
  const Profile({
    required this.id,
    required this.firstName,
    this.faculty,
    this.promotion,
    this.discoverable = true,
  });

  final String id;
  final String firstName;
  final String? faculty;
  final String? promotion;

  /// false quand l'utilisateur a choisi de ne pas apparaître dans l'annuaire.
  final bool discoverable;

  /// Tolérant par construction : une réponse inattendue ne doit pas faire
  /// planter tout l'annuaire.
  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: _str(m['id']) ?? '',
        firstName: _str(m['first_name']) ?? '',
        faculty: _str(m['faculty']),
        promotion: _str(m['promotion']),
        discoverable: m['discoverable'] is bool ? m['discoverable'] as bool : true,
      );

  Profile copyWith({bool? discoverable}) => Profile(
        id: id,
        firstName: firstName,
        faculty: faculty,
        promotion: promotion,
        discoverable: discoverable ?? this.discoverable,
      );

  String get initial =>
      firstName.isEmpty ? '?' : firstName.substring(0, 1).toUpperCase();

  String get detail =>
      [faculty, promotion].where((e) => e != null && e.isNotEmpty).join(', ');
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

  /// Retourne null si l'alarme est inutilisable (champ requis manquant) :
  /// l'appelant ignore alors cette ligne au lieu de faire échouer la liste.
  static AlarmItem? tryFromMap(Map<String, dynamic> m) {
    final id = _str(m['alarm_id']);
    final other = _str(m['other_id']);
    final createdAt = DateTime.tryParse(_str(m['created_at']) ?? '');
    if (id == null || other == null || createdAt == null) return null;

    return AlarmItem(
      id: id,
      createdAt: createdAt,
      otherId: other,
      otherName: _str(m['other_name']) ?? '',
      otherFaculty: _str(m['other_faculty']),
    );
  }
}
