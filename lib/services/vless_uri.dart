import 'dart:convert';
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
  final trimmed = raw.trim();
  
  // Extract fragment from raw string before parsing, as Uri.parse may not decode it correctly
  String? decodedFragment;
  final hashIndex = trimmed.indexOf('#');
  if (hashIndex != -1 && hashIndex < trimmed.length - 1) {
    final fragmentPart = trimmed.substring(hashIndex + 1);
    // Decode the fragment - it's URL-encoded in the URI
    // Manually decode percent-encoded UTF-8 bytes
    final bytes = <int>[];
    bool allEncoded = true;
    for (int i = 0; i < fragmentPart.length; i++) {
      if (fragmentPart[i] == '%' && i + 2 < fragmentPart.length) {
        final hex = fragmentPart.substring(i + 1, i + 3);
        final byte = int.tryParse(hex, radix: 16);
        if (byte != null) {
          bytes.add(byte);
          i += 2; // Skip the %XX
        } else {
          allEncoded = false;
          break;
        }
      } else {
        allEncoded = false;
        break;
      }
    }
    
    if (allEncoded && bytes.isNotEmpty) {
      // All percent-encoded, decode as UTF-8
      try {
        decodedFragment = utf8.decode(bytes);
      } catch (e) {
        // If UTF-8 decode fails, try Uri.decodeQueryComponent
        decodedFragment = Uri.decodeQueryComponent(fragmentPart);
      }
    } else {
      // Mixed or already decoded, use Uri.decodeQueryComponent
      try {
        decodedFragment = Uri.decodeQueryComponent(fragmentPart);
      } catch (e) {
        decodedFragment = fragmentPart;
      }
    }
  }
  
  final uri = Uri.parse(trimmed);
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
    name: decodedFragment,
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
    remark: decodedFragment,
  );
}

