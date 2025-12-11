import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/vless_profile.dart';
import '../models/vless_types.dart';
import '../services/profile_store.dart';

class ProfileNotifier extends ChangeNotifier {
  ProfileNotifier(this._store);

  final ProfileStore _store;
  final _uuid = const Uuid();

  List<VlessProfile> _profiles = [];
  String? _activeId;
  bool _initialized = false;

  List<VlessProfile> get profiles => _profiles;
  String? get activeId => _activeId;
  VlessProfile? get activeProfile {
    if (_profiles.isEmpty) return null;
    final idx = _profiles.indexWhere((p) => p.id == _activeId);
    return idx >= 0 ? _profiles[idx] : _profiles.first;
  }
  bool get initialized => _initialized;

  Future<void> init() async {
    _profiles = await _store.loadProfiles();
    _activeId = await _store.loadActiveId();
    _initialized = true;
    notifyListeners();
  }

  Future<void> addOrUpdate(VlessProfile profile) async {
    final idx = _profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      _profiles[idx] = profile;
    } else {
      _profiles = [..._profiles, profile];
      _activeId ??= profile.id;
    }
    await _persist();
  }

  Future<void> createManual({
    required String name,
    required String host,
    required int port,
    required String uuid,
    String encryption = 'none',
    String security = 'none',
    String? sni,
    List<String> alpn = const [],
    String? fingerprint,
    String? flow,
    String? realityPublicKey,
    String? realityShortId,
    VlessTransport transport = VlessTransport.tcp,
    String? path,
    String? hostHeader,
    String? remark,
  }) async {
    final profile = VlessProfile(
      id: _uuid.v4(),
      name: name,
      host: host,
      port: port,
      uuid: uuid,
      encryption: encryption,
      security: security,
      sni: sni,
      alpn: alpn,
      fingerprint: fingerprint,
      flow: flow,
      realityPublicKey: realityPublicKey,
      realityShortId: realityShortId,
      transport: transport,
      path: path,
      hostHeader: hostHeader,
      remark: remark,
    );
    await addOrUpdate(profile);
  }

  Future<VlessProfile> importUri(String uri, {String? fallbackName}) async {
    final profile = VlessProfile.fromUri(uri, fallbackName: fallbackName);
    await addOrUpdate(profile);
    return profile;
  }

  Future<void> delete(String id) async {
    _profiles = _profiles.where((p) => p.id != id).toList();
    if (_activeId == id) {
      _activeId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }
    await _persist();
  }

  Future<void> setActive(String id) async {
    _activeId = id;
    await _store.saveActiveId(id);
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store.saveProfiles(_profiles);
    if (_activeId != null) {
      await _store.saveActiveId(_activeId);
    }
    notifyListeners();
  }
}

