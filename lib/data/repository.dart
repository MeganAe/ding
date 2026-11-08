import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class Repository {
  Repository(this._c);
  final SupabaseClient _c;

  String get uid => _c.auth.currentUser!.id;

  Future<List<Profile>> campus() async {
    final rows = await _c
        .from('profiles')
        .select('id, first_name, faculty, promotion')
        .neq('id', uid)
        .neq('first_name', '')
        .order('first_name');
    return rows.map<Profile>((e) => Profile.fromMap(e)).toList();
  }

  Future<Profile?> me() async {
    final row =
        await _c.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<void> updateProfile({
    required String firstName,
    required String faculty,
    required String promotion,
  }) async {
    await _c.from('profiles').update({
      'first_name': firstName,
      'faculty': faculty.isEmpty ? null : faculty,
      'promotion': promotion.isEmpty ? null : promotion,
    }).eq('id', uid);
  }

  /// Les crushes que j'ai choisis. La base ne permet jamais de lire
  /// ceux qui m'ont choisi.
  Future<Set<String>> myCrushes() async {
    final rows = await _c.from('crushes').select('to_user');
    return rows.map<String>((e) => e['to_user'] as String).toSet();
  }

  /// Retourne true si le crush est maintenant actif, false s'il est retiré.
  Future<bool> toggleCrush(String target) async {
    final res = await _c.rpc('toggle_crush', params: {'target': target});
    return res as bool;
  }

  Future<void> sendLocation(double lat, double lng) async {
    await _c.rpc('update_location', params: {'lat': lat, 'lng': lng});
  }

  Future<List<AlarmItem>> myAlarms() async {
    final rows = await _c.rpc('my_alarms') as List<dynamic>;
    return rows
        .map<AlarmItem>((e) => AlarmItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
