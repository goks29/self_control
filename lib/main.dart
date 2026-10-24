import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'data/database/app_database.dart';
import 'presentation/lock/locked_screen.dart';
import 'presentation/navigation/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;
  runApp(const SelfControlApp());
}

class SelfControlApp extends StatelessWidget {
  const SelfControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self-Control',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/locked') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute<void>(
            builder: (_) => LockedScreen(
              packageName: args?['packageName'] as String?,
              appName: args?['appName'] as String?,
              appId: args?['appId'] as int?,
              startAtEpochMs: args?['startAtEpochMs'] as int?,
              endAtEpochMs: args?['endAtEpochMs'] as int?,
            ),
          );
        }
        return MaterialPageRoute<void>(
          builder: (_) => const MainScaffold(),
        );
      },
    );
  }
}
