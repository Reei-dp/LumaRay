import 'package:flutter/services.dart';

class VpnPlatform {
  static const _channel = MethodChannel('lumaray/vpn');

  Future<bool> prepareVpn() async {
    final result = await _channel.invokeMethod<bool>('prepareVpn');
    return result ?? false;
  }

  Future<void> startVpn({
    required String configPath,
    required String workDir,
    required String logPath,
  }) async {
    await _channel.invokeMethod('startVpn', {
      'configPath': configPath,
      'workDir': workDir,
      'logPath': logPath,
    });
  }

  Future<void> stopVpn() async {
    await _channel.invokeMethod('stopVpn');
  }
}

