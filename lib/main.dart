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
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: null, // Use system default font which supports emoji
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00D9FF),
            secondary: Color(0xFF00D9FF),
            surface: Color(0xFF000000),
            background: Color(0xFF000000),
            error: Color(0xFFCF6679),
            onPrimary: Color(0xFF000000),
            onSecondary: Color(0xFF000000),
            onSurface: Color(0xFFFFFFFF),
            onBackground: Color(0xFFFFFFFF),
            onError: Color(0xFF000000),
          ),
          scaffoldBackgroundColor: const Color(0xFF000000),
          cardColor: const Color(0xFF0A0A0A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF000000),
            foregroundColor: Color(0xFFFFFFFF),
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF0A0A0A),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF00D9FF),
            foregroundColor: Color(0xFF000000),
          ),
        ),
        themeMode: ThemeMode.dark,
        home: const HomeScreen(),
      ),
    );
  }
}
