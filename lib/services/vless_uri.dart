import 'package:uuid/uuid.dart';

import '../models/vless_types.dart';

const _uuid = Uuid();

class ParsedVlessUri {
  final String id;
  final String host;
  final int port;
  final String uuid;
  final String? name;
  final String? encryption;
  final String? security;
  final String? sni;
  final List<String>? alpn;
  final String? fingerprint;
  final String? flow;
  final String? realityPublicKey;
  final String? realityShortId;
  final VlessTransport? transport;
  final String? path;
  final String? hostHeader;
  final String? remark;

  ParsedVlessUri({
    required this.id,
    required this.host,
    required this.port,
    required this.uuid,
    this.name,
    this.encryption,
    this.security,
    this.sni,
    this.alpn,
    this.fingerprint,
    this.flow,
    this.realityPublicKey,
    this.realityShortId,
    this.transport,
    this.path,
    this.hostHeader,
    this.remark,
  });
}

ParsedVlessUri parseVlessUri(String raw) {
  final uri = Uri.parse(raw.trim());
  if (uri.scheme != 'vless') {
    throw FormatException('URI scheme must be vless://');
  }

  final uuid = uri.userInfo.isNotEmpty ? uri.userInfo.split(':').first : '';
  if (uuid.isEmpty) {
    throw FormatException('Missing UUID in VLESS URI');
  }

  final host = uri.host;
  final port = uri.port == 0 ? 443 : uri.port;

  final params = uri.queryParameters;
  final alpnRaw = params['alpn'];
  final alpn =
      alpnRaw != null && alpnRaw.isNotEmpty ? alpnRaw.split(',') : <String>[];
  final transport = transportFromString(params['type']);

  return ParsedVlessUri(
    id: _uuid.v4(),
    host: host,
    port: port,
    uuid: uuid,
    name: uri.fragment.isNotEmpty ? uri.fragment : null,
    encryption: params['encryption'],
    security: params['security'],
    sni: params['sni'],
    alpn: alpn,
    fingerprint: params['fp'],
    flow: params['flow'],
    realityPublicKey: params['pbk'] ?? params['publicKey'],
    realityShortId: params['sid'] ?? params['shortId'],
    transport: transport,
    path: params['path'] ?? params['serviceName'],
    hostHeader: params['host'],
    remark: uri.fragment.isNotEmpty ? uri.fragment : null,
  );
}

