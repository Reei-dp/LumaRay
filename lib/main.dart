import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'notifiers/profile_notifier.dart';
import 'notifiers/vpn_notifier.dart';
import 'screens/home_screen.dart';
import 'services/profile_store.dart';
import 'services/xray_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProfileStore.create();
  final profileNotifier = ProfileNotifier(store);
  await profileNotifier.init();
  final xrayRunner = XrayRunner();
  await xrayRunner.prepare();

  runApp(MyApp(profileNotifier: profileNotifier, xrayRunner: xrayRunner));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.profileNotifier, required this.xrayRunner});

  final ProfileNotifier profileNotifier;
  final XrayRunner xrayRunner;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profileNotifier),
        ChangeNotifierProvider(create: (_) => VpnNotifier(xrayRunner)),
      ],
      child: MaterialApp(
        title: 'LumaRay VLESS',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
