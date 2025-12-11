import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/vless_profile.dart';
import '../models/vless_types.dart';

class XrayRunner {
  static const _assetDir = 'assets/xray';

  String? _workDir;
  String? _geoipPath;
  String? _geositePath;
  String? _logPath;

  String? get logPath => _logPath;

  Future<void> prepare() async {
    final dir = await getApplicationSupportDirectory();
    final workDir = Directory(p.join(dir.path, 'xray'));
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    _workDir = workDir.path;

    final geoipPath = p.join(workDir.path, 'geoip.dat');
    final geositePath = p.join(workDir.path, 'geosite.dat');

    await _copyAsset('$_assetDir/geoip.dat', geoipPath);
    await _copyAsset('$_assetDir/geosite.dat', geositePath);

    _geoipPath = geoipPath;
    _geositePath = geositePath;
    _logPath = p.join(workDir.path, 'log.txt');
  }

  Future<XrayConfigContext> prepareConfig(VlessProfile profile) async {
    final workDir = _workDir ?? (await _ensurePrepared());
    final configPath = p.join(workDir, 'config.json');
    final logPath = _logPath ?? p.join(workDir, 'log.txt');

    // truncate old log
    try {
      final logFile = File(logPath);
      if (await logFile.exists()) {
        await logFile.writeAsString('');
      }
    } catch (_) {}

    final config = _buildConfig(profile, workDir);
    final configFile = File(configPath);
    await configFile.writeAsString(jsonEncode(config));
    return XrayConfigContext(
      configPath: configPath,
      workDir: workDir,
      logPath: logPath,
    );
  }

  Future<String> _ensurePrepared() async {
    if (_workDir != null) return _workDir!;
    await prepare();
    return _workDir!;
  }

  Future<void> _copyAsset(String assetPath, String destPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final file = File(destPath);
    await file.writeAsBytes(bytes, flush: true);
  }

  Map<String, dynamic> _buildConfig(VlessProfile profile, String workDir) {
    final tlsEnabled = profile.security != 'none';
    final transport = profile.transport;
    Map<String, dynamic>? transportSettings;

    if (transport == VlessTransport.ws) {
      transportSettings = {
        'type': 'ws',
        'path': profile.path ?? '/',
        if (profile.hostHeader != null)
          'headers': {
            'Host': profile.hostHeader,
          },
      };
    } else if (transport == VlessTransport.grpc) {
      transportSettings = {
        'type': 'grpc',
        'serviceName': profile.path ?? '',
      };
    } else if (transport == VlessTransport.h2) {
      transportSettings = {
        'type': 'http',
        'path': profile.path ?? '/',
        if (profile.hostHeader != null)
          'host': [profile.hostHeader],
      };
    }

    final outbound = {
      'type': 'vless',
      'tag': 'proxy',
      'server': profile.host,
      'server_port': profile.port,
      'uuid': profile.uuid,
      'packet_encoding': '',
      'domain_strategy': 'prefer_ipv4',
      'tls': tlsEnabled
          ? {
              'enabled': true,
              'insecure': false,
              'server_name': profile.sni ?? profile.host,
              if (profile.alpn.isNotEmpty) 'alpn': profile.alpn,
              if (profile.fingerprint != null)
                'utls': {'enabled': true, 'fingerprint': profile.fingerprint},
              if (profile.security == 'reality' &&
                  profile.realityPublicKey != null &&
                  profile.realityShortId != null)
                'reality': {
                  'enabled': true,
                  'public_key': profile.realityPublicKey!,
                  'short_id': profile.realityShortId!,
                },
            }
          : {
              'enabled': false,
            },
      if (transportSettings != null) 'transport': transportSettings,
    };

    return {
      'log': {
        'level': 'debug',
        'timestamp': true,
      },
      'dns': {
        'independent_cache': true,
        'servers': [
          {
            'tag': 'dns-local',
            'address': 'local',
            'detour': 'direct',
          },
          {
            'tag': 'dns-direct',
            'address': '1.1.1.1',
            'detour': 'direct',
            'strategy': 'ipv4_only',
          },
          {
            'tag': 'dns-block',
            'address': 'rcode://success',
          },
        ],
        'rules': [
          {
            'outbound': ['any'],
            'server': 'dns-direct',
          },
          {
            'disable_cache': true,
            'domain_suffix': [
              'appcenter.ms',
              'firebase.io',
              'crashlytics.com',
            ],
            'server': 'dns-block',
          },
        ],
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30'],
          'auto_route': true,
          'strict_route': false,
          'mtu': 1500,
          'stack': 'mixed',
          'sniff': true,
          'sniff_override_destination': false,
          'endpoint_independent_nat': true,
          'domain_strategy': 'ipv4_only',
        },
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': 2080,
          'sniff': true,
          'sniff_override_destination': false,
          'domain_strategy': 'ipv4_only',
        }
      ],
      'outbounds': [
        outbound,
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'direct',
          'tag': 'bypass',
        },
      ],
      'route': {
        'auto_detect_interface': true,
        'rules': [
          {
            'action': 'hijack-dns',
            'port': [53],
          },
          {
            'action': 'hijack-dns',
            'protocol': ['dns'],
          },
          {
            'outbound': 'direct',
            'domain': [profile.host],
          },
          {
            'action': 'reject',
            'domain_suffix': [
              'appcenter.ms',
              'firebase.io',
              'crashlytics.com',
            ],
          },
          {
            'action': 'reject',
            'ip_cidr': ['224.0.0.0/3', 'ff00::/8'],
            'source_ip_cidr': ['224.0.0.0/3', 'ff00::/8'],
          },
        ],
        'final': 'proxy',
      },
    };
  }
}

class XrayConfigContext {
  final String configPath;
  final String workDir;
  final String logPath;

  XrayConfigContext({
    required this.configPath,
    required this.workDir,
    required this.logPath,
  });
}


