import 'package:flutter/foundation.dart';

import '../models/vless_profile.dart';
import '../services/vpn_platform.dart';
import '../services/xray_runner.dart';

enum VpnStatus { disconnected, connecting, connected, error }

class VpnNotifier extends ChangeNotifier {
  VpnNotifier(this._runner, {VpnPlatform? platform})
      : _platform = platform ?? VpnPlatform();

  final XrayRunner _runner;
  final VpnPlatform _platform;
  VpnStatus _status = VpnStatus.disconnected;
  VlessProfile? _current;
  String? _lastError;

  VpnStatus get status => _status;
  VlessProfile? get current => _current;
  String? get lastError => _lastError;
  String? _logPath;
  String? get logPath => _logPath;

  Future<void> connect(VlessProfile profile) async {
    _status = VpnStatus.connecting;
    _current = profile;
    _lastError = null;
    notifyListeners();

    try {
      final prepared = await _runner.prepareConfig(profile);
      _logPath = prepared.logPath;
      await _platform.prepareVpn();
      // Use libbox (no binPath) instead of external binary
      await _platform.startVpn(
        configPath: prepared.configPath,
        workDir: prepared.workDir,
        logPath: prepared.logPath,
      );
      _status = VpnStatus.connected;
      notifyListeners();
    } catch (e) {
      _status = VpnStatus.error;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _platform.stopVpn();
    _status = VpnStatus.disconnected;
    _current = null;
    _logPath = null;
    notifyListeners();
  }
}

