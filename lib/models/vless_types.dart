enum VlessTransport { tcp, ws, grpc, h2 }

String transportToString(VlessTransport transport) {
  switch (transport) {
    case VlessTransport.tcp:
      return 'tcp';
    case VlessTransport.ws:
      return 'ws';
    case VlessTransport.grpc:
      return 'grpc';
    case VlessTransport.h2:
      return 'h2';
  }
}

VlessTransport transportFromString(String? raw) {
  switch (raw) {
    case 'ws':
      return VlessTransport.ws;
    case 'grpc':
      return VlessTransport.grpc;
    case 'h2':
      return VlessTransport.h2;
    case 'tcp':
    default:
      return VlessTransport.tcp;
  }
}

