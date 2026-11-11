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
    this.email,
    this.discoverable = true,
  });

  final String id;
  final String firstName;
  final String? faculty;
  final String? promotion;

  /// Renseigné uniquement pour mon propre profil (/me) : l'API ne le renvoie
  /// jamais pour les autres.
  final String? email;

  /// false quand l'utilisateur a choisi de ne pas apparaître dans l'annuaire.
  final bool discoverable;

  /// Tolérant par construction : une réponse inattendue ne doit pas faire
  /// planter tout l'annuaire.
  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: _str(m['id']) ?? '',
        firstName: _str(m['first_name']) ?? '',
        faculty: _str(m['faculty']),
        promotion: _str(m['promotion']),
        email: _str(m['email']),
        discoverable: m['discoverable'] is bool ? m['discoverable'] as bool : true,
      );

  Profile copyWith({bool? discoverable}) => Profile(
        id: id,
        firstName: firstName,
        faculty: faculty,
        promotion: promotion,
        email: email,
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


/// Une page de l'annuaire : les profils, le total, et où continuer.
class CampusPage {
  const CampusPage({
    required this.items,
    required this.total,
    this.nextOffset,
  });

  final List<Profile> items;

  /// Nombre de profils correspondant à la recherche, pas seulement à la page.
  final int total;

  /// `null` quand tout a été chargé.
  final int? nextOffset;

  static CampusPage fromMap(Map<String, dynamic> m) {
    final rows = m['items'];
    final items = rows is List
        ? rows
            .whereType<Map<String, dynamic>>()
            .map(Profile.fromMap)
            .where((p) => p.id.isNotEmpty)
            .toList()
        : <Profile>[];
    final total = m['total'] is int ? m['total'] as int : items.length;
    final next = m['next_offset'];
    return CampusPage(
      items: items,
      total: total,
      nextOffset: next is int ? next : null,
    );
  }
}

/// Réglages publics renvoyés par `GET /config`.
class ServerConfig {
  const ServerConfig({
    required this.alarmRadiusMeters,
    required this.alarmPollSeconds,
    required this.locationIntervalSeconds,
  });

  final int alarmRadiusMeters;
  final int alarmPollSeconds;
  final int locationIntervalSeconds;

  static ServerConfig? tryFromMap(dynamic m) {
    if (m is! Map) return null;
    final radius = m['alarm_radius_meters'];
    if (radius is! num) return null;
    return ServerConfig(
      alarmRadiusMeters: radius.round(),
      alarmPollSeconds: m['alarm_poll_seconds'] is num
          ? (m['alarm_poll_seconds'] as num).round()
          : 20,
      locationIntervalSeconds: m['location_interval_seconds'] is num
          ? (m['location_interval_seconds'] as num).round()
          : 120,
    );
  }
}
