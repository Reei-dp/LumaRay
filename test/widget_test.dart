// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumaray/notifiers/profile_notifier.dart';
import 'package:lumaray/notifiers/vpn_notifier.dart';
import 'package:lumaray/screens/home_screen.dart';
import 'package:lumaray/services/profile_store.dart';
import 'package:lumaray/services/xray_runner.dart';
import 'package:lumaray/services/vpn_platform.dart';

class _FakeRunner extends XrayRunner {
  @override
  Future<void> prepare() async {}

  @override
  Future<XrayConfigContext> prepareConfig(profile) async {
    return XrayConfigContext(
      binPath: '/tmp/xray',
      configPath: '/tmp/config.json',
      workDir: '/tmp',
      logPath: '/tmp/log.txt',
    );
  }
}

class _FakePlatform extends VpnPlatform {
  @override
  Future<bool> prepareVpn() async => true;

  @override
  Future<void> startVpn({required String binPath, required String configPath, required String workDir, required String logPath}) async {}

  @override
  Future<void> stopVpn() async {}
}

void main() {
  testWidgets('Home screen renders', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final store = await ProfileStore.create();
    final profileNotifier = ProfileNotifier(store);
    await profileNotifier.init();
    final runner = _FakeRunner();
    final platform = _FakePlatform();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: profileNotifier),
          ChangeNotifierProvider(create: (_) => VpnNotifier(runner, platform: platform)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.text('LumaRay VLESS'), findsOneWidget);
  });
}
