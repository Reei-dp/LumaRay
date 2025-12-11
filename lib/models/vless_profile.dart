import 'dart:convert';

import '../models/vless_types.dart';
import '../services/vless_uri.dart';

class VlessProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String uuid;
  final String encryption; // usually "none"
  final String security; // none | tls | reality
  final String? sni;
  final List<String> alpn;
  final String? fingerprint;
  final String? flow;
  final String? realityPublicKey; // For Reality protocol
  final String? realityShortId; // For Reality protocol
  final VlessTransport transport;
  final String? path;
  final String? hostHeader;
  final String? remark;

  const VlessProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.uuid,
    this.encryption = 'none',
    this.security = 'none',
    this.sni,
    this.alpn = const [],
    this.fingerprint,
    this.flow,
    this.realityPublicKey,
    this.realityShortId,
    this.transport = VlessTransport.tcp,
    this.path,
    this.hostHeader,
    this.remark,
  });

  VlessProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? uuid,
    String? encryption,
    String? security,
    String? sni,
    List<String>? alpn,
    String? fingerprint,
    String? flow,
    String? realityPublicKey,
    String? realityShortId,
    VlessTransport? transport,
    String? path,
    String? hostHeader,
    String? remark,
  }) {
    return VlessProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      uuid: uuid ?? this.uuid,
      encryption: encryption ?? this.encryption,
      security: security ?? this.security,
      sni: sni ?? this.sni,
      alpn: alpn ?? this.alpn,
      fingerprint: fingerprint ?? this.fingerprint,
      flow: flow ?? this.flow,
      realityPublicKey: realityPublicKey ?? this.realityPublicKey,
      realityShortId: realityShortId ?? this.realityShortId,
      transport: transport ?? this.transport,
      path: path ?? this.path,
      hostHeader: hostHeader ?? this.hostHeader,
      remark: remark ?? this.remark,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'uuid': uuid,
      'encryption': encryption,
      'security': security,
      'sni': sni,
      'alpn': alpn,
      'fingerprint': fingerprint,
      'flow': flow,
      'realityPublicKey': realityPublicKey,
      'realityShortId': realityShortId,
      'transport': transportToString(transport),
      'path': path,
      'hostHeader': hostHeader,
      'remark': remark,
    };
  }

  factory VlessProfile.fromMap(Map<String, dynamic> map) {
    return VlessProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      host: map['host'] as String,
      port: (map['port'] as num).toInt(),
      uuid: map['uuid'] as String,
      encryption: (map['encryption'] as String?) ?? 'none',
      security: (map['security'] as String?) ?? 'none',
      sni: map['sni'] as String?,
      alpn: (map['alpn'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      fingerprint: map['fingerprint'] as String?,
      flow: map['flow'] as String?,
      realityPublicKey: map['realityPublicKey'] as String?,
      realityShortId: map['realityShortId'] as String?,
      transport: transportFromString(map['transport'] as String?),
      path: map['path'] as String?,
      hostHeader: map['hostHeader'] as String?,
      remark: map['remark'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory VlessProfile.fromJson(String source) =>
      VlessProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);

  factory VlessProfile.fromUri(String uri, {String? fallbackName}) {
    final parsed = parseVlessUri(uri);
    return VlessProfile(
      id: parsed.id,
      name: parsed.name ?? fallbackName ?? parsed.host,
      host: parsed.host,
      port: parsed.port,
      uuid: parsed.uuid,
      encryption: parsed.encryption ?? 'none',
      security: parsed.security ?? 'none',
      sni: parsed.sni,
      alpn: parsed.alpn ?? const [],
      fingerprint: parsed.fingerprint,
      flow: parsed.flow,
      realityPublicKey: parsed.realityPublicKey,
      realityShortId: parsed.realityShortId,
      transport: parsed.transport ?? VlessTransport.tcp,
      path: parsed.path,
      hostHeader: parsed.hostHeader,
      remark: parsed.remark,
    );
  }

  String toUri() {
    final query = <String, String>{};
    query['encryption'] = encryption;
    if (security.isNotEmpty && security != 'none') {
      query['security'] = security;
    }
    if (sni?.isNotEmpty ?? false) query['sni'] = sni!;
    if (alpn.isNotEmpty) query['alpn'] = alpn.join(',');
    if (fingerprint?.isNotEmpty ?? false) query['fp'] = fingerprint!;
    if (flow?.isNotEmpty ?? false) query['flow'] = flow!;
    if (transport != VlessTransport.tcp) {
      query['type'] = transportToString(transport);
    }
    if (path?.isNotEmpty ?? false) query['path'] = path!;
    if (hostHeader?.isNotEmpty ?? false) query['host'] = hostHeader!;
    if (realityPublicKey?.isNotEmpty ?? false) query['pbk'] = realityPublicKey!;
    if (realityShortId?.isNotEmpty ?? false) query['sid'] = realityShortId!;

    final uri = Uri(
      scheme: 'vless',
      userInfo: uuid,
      host: host,
      port: port,
      queryParameters: query.isEmpty ? null : query,
      fragment: name,
    );
    return uri.toString();
  }
}

