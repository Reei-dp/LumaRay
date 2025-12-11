import 'package:shared_preferences/shared_preferences.dart';

import '../models/vless_profile.dart';

class ProfileStore {
  ProfileStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _profilesKey = 'vless_profiles';
  static const _activeKey = 'vless_active_profile';

  static Future<ProfileStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ProfileStore._(prefs);
  }

  Future<List<VlessProfile>> loadProfiles() async {
    final raw = _prefs.getStringList(_profilesKey) ?? [];
    return raw
        .map((e) => VlessProfile.fromJson(e))
        .whereType<VlessProfile>()
        .toList();
  }

  Future<void> saveProfiles(List<VlessProfile> profiles) async {
    final encoded = profiles.map((p) => p.toJson()).toList();
    await _prefs.setStringList(_profilesKey, encoded);
  }

  Future<String?> loadActiveId() async {
    return _prefs.getString(_activeKey);
  }

  Future<void> saveActiveId(String? id) async {
    if (id == null) {
      await _prefs.remove(_activeKey);
    } else {
      await _prefs.setString(_activeKey, id);
    }
  }
}

