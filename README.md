# LumaRay

A modern Android VPN client for the VLESS protocol, built with Flutter and powered by sing-box.

## Features

- **VLESS Protocol Support**: Full support for VLESS with TLS, Reality, and various transport types
- **Profile Management**: Add, edit, delete, and switch between multiple VLESS profiles
- **Import/Export**: Import profiles from clipboard or file, export and share configurations
- **Reality Support**: Built-in support for Reality protocol with public key and short ID
- **Transport Types**: Support for TCP, WebSocket (WS), gRPC, and HTTP/2 transports
- **Native Integration**: Uses embedded libbox library for optimal performance
- **Connection Status**: Real-time VPN connection status and statistics
- **Logs Viewing**: View sing-box logs directly in the app
- **Modern UI**: Clean and intuitive Material Design interface

## Architecture

LumaRay is built with Flutter for cross-platform UI and uses native Android components for VPN functionality:

- **Flutter**: UI layer and business logic
- **libbox**: Embedded sing-box library via JNI for VPN core functionality
- **VpnService**: Android VPN service for TUN interface management
- **Platform Channels**: Communication between Flutter and native Android code

## Project Structure

```
lib/
├── main.dart                 # Application entry point
├── models/                   # Data models
│   ├── vless_profile.dart   # VLESS profile model
│   └── vless_types.dart     # Transport types and utilities
├── services/                 # Business logic services
│   ├── profile_store.dart   # Profile persistence
│   ├── vless_uri.dart       # URI parser
│   ├── vpn_platform.dart    # VPN platform interface
│   └── xray_runner.dart     # sing-box configuration builder
├── notifiers/                # State management
│   ├── profile_notifier.dart
│   └── vpn_notifier.dart
└── screens/                  # UI screens
    ├── home_screen.dart
    ├── profile_form_screen.dart
    └── log_screen.dart

android/
└── app/src/main/kotlin/com/example/lumaray/
    ├── MainActivity.kt              # Method channel handler
    ├── LibboxVpnService.kt         # VPN service implementation
    ├── DefaultNetworkMonitor.kt    # Network monitoring
    └── LocalResolver.kt            # DNS resolver
```

## Requirements

- Flutter SDK (latest stable)
- Android SDK (API level 21+)
- Android device with VPN support
- libbox.aar and libbox.so (native libraries)

## Building

1. Clone the repository:
```bash
git clone <repository-url>
cd LumaRay
```

2. Install dependencies:
```bash
flutter pub get
```

3. Ensure libbox libraries are in place:
   - `android/app/libs/libbox.aar`
   - `android/app/src/main/jniLibs/arm64-v8a/libbox.so`

4. Build the APK:
```bash
flutter build apk
```

Or run in debug mode:
```bash
flutter run
```

## Usage

1. **Add a Profile**: Tap the "+" button to add a new VLESS profile manually or import from URI
2. **Import Profile**: Use the import button to import from clipboard or file
3. **Connect**: Select a profile and tap "Connect" to start the VPN
4. **View Logs**: Access logs from the home screen to troubleshoot connection issues
5. **Export/Share**: Long-press a profile to export or share the configuration

## VLESS URI Format

LumaRay supports standard VLESS URI format:
```
vless://uuid@host:port?security=tls&sni=example.com&alpn=h2,http/1.1&fp=chrome&type=ws&path=/path&host=example.com#ProfileName
```

### Parameters

- `security`: `none`, `tls`, or `reality`
- `sni`: Server Name Indication for TLS
- `alpn`: Application-Layer Protocol Negotiation (comma-separated)
- `fp`: uTLS fingerprint (e.g., `chrome`, `firefox`)
- `type`: Transport type (`tcp`, `ws`, `grpc`, `h2`)
- `path`: Path for WS/H2 transport
- `host`: Host header for WS/H2 transport
- `pbk`: Reality public key
- `sid`: Reality short ID

## Configuration

The app generates sing-box configuration automatically based on the selected profile. Key features:

- **TUN Interface**: Automatic TUN interface creation and routing
- **DNS**: Configurable DNS servers with hijacking support
- **Routing**: Automatic route detection and traffic routing
- **Network Monitoring**: Real-time network interface monitoring

## Permissions

The app requires the following Android permissions:

- `INTERNET`: For network connectivity
- `ACCESS_NETWORK_STATE`: For network monitoring
- `BIND_VPN_SERVICE`: For VPN service binding
- `FOREGROUND_SERVICE`: For persistent VPN connection

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]

## Acknowledgments

- [sing-box](https://github.com/SagerNet/sing-box) - The underlying VPN core
- [SagerNet/sing-box-for-android](https://github.com/SagerNet/sing-box-for-android) - Reference implementation for libbox integration
