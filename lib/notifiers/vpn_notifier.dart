import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/vless_profile.dart';
import '../models/vless_types.dart';
import '../services/vpn_platform.dart';
import '../services/xray_runner.dart';

enum VpnStatus { disconnected, connecting, connected, error }

class VpnNotifier extends ChangeNotifier {
  VpnNotifier(this._runner, {VpnPlatform? platform})
      : _platform = platform ?? VpnPlatform() {
    // Listen for VPN stop events from native side
    _platform.onVpnStopped = () {
      if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
        _status = VpnStatus.disconnected;
        _current = null;
        _logPath = null;
        _uploadBytes = 0;
        _downloadBytes = 0;
        _statsTimer?.cancel();
        _statsTimer = null;
        notifyListeners();
      }
    };
  }

  final XrayRunner _runner;
  final VpnPlatform _platform;
  VpnStatus _status = VpnStatus.disconnected;
  VlessProfile? _current;
  String? _lastError;
  int _uploadBytes = 0;
  int _downloadBytes = 0;
  Timer? _statsTimer;

  VpnStatus get status => _status;
  VlessProfile? get current => _current;
  String? get lastError => _lastError;
  String? _logPath;
  String? get logPath => _logPath;
  int get uploadBytes => _uploadBytes;
  int get downloadBytes => _downloadBytes;

  Future<void> connect(VlessProfile profile) async {
    _status = VpnStatus.connecting;
    _current = profile;
    _lastError = null;
    notifyListeners();

    try {
      // Request notification permission for Android 13+
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        }
      }
      
      final prepared = await _runner.prepareConfig(profile);
      _logPath = prepared.logPath;
      await _platform.prepareVpn();
      // Use libbox (no binPath) instead of external binary
      await _platform.startVpn(
        configPath: prepared.configPath,
        workDir: prepared.workDir,
        logPath: prepared.logPath,
        profileName: profile.name,
        transport: transportToString(profile.transport),
      );
      _status = VpnStatus.connected;
      _startStatsTimer();
      notifyListeners();
    } catch (e) {
      _status = VpnStatus.error;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_status == VpnStatus.connected) {
        try {
          final stats = await _platform.getStats();
          updateStats(stats['upload'] ?? 0, stats['download'] ?? 0);
        } catch (e) {
          // Ignore errors
        }
      }
    });
  }

  Future<void> disconnect() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    await _platform.stopVpn();
    _status = VpnStatus.disconnected;
    _current = null;
    _logPath = null;
    _uploadBytes = 0;
    _downloadBytes = 0;
    notifyListeners();
  }

  void updateStats(int upload, int download) {
    _uploadBytes = upload;
    _downloadBytes = download;
    notifyListeners();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _platform.dispose();
    super.dispose();
  }
}

