import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'application/services/database_maintenance_service.dart';
import 'core/platform/blocking_platform_channel.dart';
import 'core/theme/app_theme.dart';
import 'data/database/app_database.dart';
import 'data/repositories/block_session_repository_impl.dart';
import 'presentation/lock/locked_screen.dart';
import 'presentation/navigation/main_scaffold.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrap());
}

/// Blocking is currently implemented only by the Android native host.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.isSupported, this.initialize});

  final bool? isSupported;
  final Future<Map<String, dynamic>?> Function()? initialize;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _loading = true;
  bool _ready = false;
  String? _error;
  Map<String, dynamic>? _initialLock;
  final BlockingPlatformChannel _channel = BlockingPlatformChannel();

  bool get _supported =>
      widget.isSupported ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    if (_supported) _initialize();
  }

  Future<Map<String, dynamic>?> _initializeDependencies() async {
    final database = AppDatabase.instance;
    await database.database;
    await DatabaseMaintenanceService(
      database: database,
      channel: _channel,
    ).synchronizeAfterRecovery();
    return _channel.getInitialLockIntent();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final initialLock =
          await (widget.initialize ?? _initializeDependencies)();
      if (!mounted) return;
      setState(() {
        _initialLock = initialLock;
        _ready = true;
      });
    } catch (error, stack) {
      developer.log(
        'Application initialization failed (${error.runtimeType})',
        name: 'self_control.startup',
        stackTrace: stack,
      );
      if (mounted) {
        setState(
          () => _error = 'Data tidak direset otomatis. Coba lagi atau periksa konfigurasi aplikasi.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_supported && _ready) {
      return SelfControlApp(
        initialLockIntent: _initialLock,
        platformChannel: _channel,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_supported) ...[
                    const Text('Platform belum didukung'),
                    const SizedBox(height: 12),
                    const Text(
                      'Self-Control saat ini memerlukan Android untuk layanan aksesibilitas dan pemblokiran aplikasi.',
                      textAlign: TextAlign.center,
                    ),
                  ] else if (_loading)
                    const CircularProgressIndicator()
                  else ...[
                    const Text('Gagal menyiapkan aplikasi'),
                    const SizedBox(height: 12),
                    Text(_error ?? '', textAlign: TextAlign.center),
                    TextButton(
                      onPressed: _initialize,
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SelfControlApp extends StatefulWidget {
  const SelfControlApp({
    super.key,
    this.navigatorKey,
    this.platformChannel,
    this.initialLockIntent,
  });

  final GlobalKey<NavigatorState>? navigatorKey;
  final BlockingPlatformChannel? platformChannel;
  final Map<String, dynamic>? initialLockIntent;

  @override
  State<SelfControlApp> createState() => _SelfControlAppState();
}

class _SelfControlAppState extends State<SelfControlApp> {
  late final BlockingPlatformChannel _channel;
  late final GlobalKey<NavigatorState> _navKey;
  String? _currentLockedPackage;

  @override
  void initState() {
    super.initState();
    _navKey = widget.navigatorKey ?? navigatorKey;
    _channel = widget.platformChannel ?? BlockingPlatformChannel();
    _channel.registerLockRequestListener(_handleLockRequest);

    if (widget.initialLockIntent != null) {
      final pkg = widget.initialLockIntent!['packageName'] as String?;
      final blockedAt =
          (widget.initialLockIntent!['blockedAt'] as num?)?.toInt() ??
          (widget.initialLockIntent!['startAtEpochMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      if (pkg != null && pkg.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateToLocked(pkg, blockedAt);
          }
        });
      }
    } else {
      _checkInitialLockIntent();
    }
  }

  @override
  void dispose() {
    _channel.unregisterLockRequestListener(_handleLockRequest);
    super.dispose();
  }

  Future<void> _checkInitialLockIntent() async {
    final intent = await _channel.getInitialLockIntent();
    if (intent != null && mounted) {
      final pkg = intent['packageName'] as String?;
      final blockedAt =
          (intent['blockedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      if (pkg != null && pkg.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateToLocked(pkg, blockedAt);
          }
        });
      }
    }
  }

  void _handleLockRequest(String packageName, int blockedAt) {
    if (packageName.isEmpty || _currentLockedPackage == packageName) {
      return;
    }
    _navigateToLocked(packageName, blockedAt);
  }

  void _navigateToLocked(String packageName, int blockedAt) {
    final nav = _navKey.currentState;
    if (nav == null) return;
    _currentLockedPackage = packageName;

    nav
        .pushNamedAndRemoveUntil(
          '/locked',
          (route) => route.isFirst,
          arguments: {'packageName': packageName, 'startAtEpochMs': blockedAt},
        )
        .then((_) {
          if (_currentLockedPackage == packageName) {
            _currentLockedPackage = null;
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Self-Control',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/locked') {
          final args =
              (settings.arguments as Map<String, dynamic>?) ??
              widget.initialLockIntent;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => LockedScreen(
              packageName: args?['packageName'] as String?,
              appName: args?['appName'] as String?,
              appId: args?['appId'] as int?,
              startAtEpochMs:
                  (args?['startAtEpochMs'] ?? args?['blockedAt']) as int?,
              endAtEpochMs: args?['endAtEpochMs'] as int?,
              platformChannel: _channel,
              blockSessionRepository: BlockSessionRepositoryImpl(),
            ),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => MainScaffold(platformChannel: _channel),
        );
      },
    );
  }
}
