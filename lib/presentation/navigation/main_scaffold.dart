import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/platform/blocking_platform_channel.dart';

import 'dart:developer' as developer;

import '../../application/services/runtime_sync_service.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/activity_log_repository_impl.dart';
import '../../data/repositories/blocked_app_repository.dart';
import '../../data/repositories/blocked_app_repository_impl.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/temporary_unlock_repository.dart';
import '../../data/repositories/temporary_unlock_repository_impl.dart';
import '../application/application_selection_screen.dart';
import '../home/dashboard_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/revoked_permission_banner.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({
    super.key,
    this.activityLogRepository,
    this.blockedAppRepository,
    this.platformChannel,
    this.settingsRepository,
    this.temporaryUnlockRepository,
    this.initialIndex = 0,
  });

  final ActivityLogRepository? activityLogRepository;
  final BlockedAppRepository? blockedAppRepository;
  final BlockingPlatformChannel? platformChannel;
  final SettingsRepository? settingsRepository;
  final TemporaryUnlockRepository? temporaryUnlockRepository;
  final int initialIndex;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with WidgetsBindingObserver {
  late int _currentIndex;
  late final BlockingPlatformChannel _platformChannel;
  late final RuntimeSyncService _runtimeSync;
  bool _isAccessibilityDisabled = false;
  bool _isSynchronizing = false;
  bool _syncRequested = false;
  String? _syncError;
  int _dataRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _platformChannel = widget.platformChannel ?? BlockingPlatformChannel();
    _runtimeSync = RuntimeSyncService(
      channel: _platformChannel,
      unlocks:
          widget.temporaryUnlockRepository ?? TemporaryUnlockRepositoryImpl(),
      logs: widget.activityLogRepository ?? ActivityLogRepositoryImpl(),
      apps: widget.blockedAppRepository ?? BlockedAppRepositoryImpl(),
    );
    _synchronize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Permission status must not wait behind database reconciliation.
      _refreshAccessibilityStatus();
      _synchronize();
    }
  }

  Future<void> _checkAccessibilityStatus() async {
    final isEnabled = await _platformChannel.isAccessibilityServiceEnabled();
    if (mounted) {
      setState(() {
        _isAccessibilityDisabled = !isEnabled;
      });
    }
  }

  Future<void> _refreshAccessibilityStatus() async {
    try {
      await _checkAccessibilityStatus();
    } catch (error, stack) {
      _reportSyncError(error, stack);
    }
  }

  Future<void> _onFixAccessibilityPressed() async {
    try {
      if (!await _platformChannel.openAccessibilitySettings()) {
        throw StateError('Accessibility settings could not be opened');
      }
      if (mounted) await _synchronize();
    } catch (error, stack) {
      _reportSyncError(error, stack);
    }
  }

  Future<void> _synchronize() async {
    if (!mounted) return;
    if (_isSynchronizing) {
      _syncRequested = true;
      return;
    }
    _isSynchronizing = true;
    try {
      await _checkAccessibilityStatus();
      await _runtimeSync.synchronize();
      if (mounted) setState(() => _syncError = null);
    } catch (error, stack) {
      _reportSyncError(error, stack);
    } finally {
      _isSynchronizing = false;
      if (mounted) {
        setState(() => _dataRevision++);
        if (_syncRequested) {
          _syncRequested = false;
          _synchronize();
        }
      }
    }
  }

  void _reportSyncError(Object error, StackTrace stack) {
    developer.log(
      'Runtime synchronization failed (${error.runtimeType})',
      name: 'self_control.sync',
      stackTrace: stack,
    );
    if (mounted) {
      setState(
        () => _syncError = 'Sinkronisasi data belum selesai. Coba lagi.',
      );
    }
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
      _dataRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Dashboard', 'Pilih Aplikasi'];

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(titles[_currentIndex]),
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.cream,
      ),
      drawer: Drawer(
        backgroundColor: AppColors.cream,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.darkGreen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Self-Control',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: AppColors.cream),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fokus & Disiplin Digital',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.peach),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                _currentIndex == 0 ? Icons.dashboard : Icons.dashboard_outlined,
                color: _currentIndex == 0
                    ? AppColors.brown
                    : AppColors.darkGreen,
              ),
              title: Text(
                'Beranda',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: _currentIndex == 0
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: _currentIndex == 0
                      ? AppColors.brown
                      : AppColors.darkGreen,
                ),
              ),
              selected: _currentIndex == 0,
              selectedTileColor: AppColors.peach.withValues(alpha: 0.35),
              onTap: () {
                _onTabSelected(0);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: Icon(
                _currentIndex == 1 ? Icons.apps : Icons.apps_outlined,
                color: _currentIndex == 1
                    ? AppColors.brown
                    : AppColors.darkGreen,
              ),
              title: Text(
                'Aplikasi',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: _currentIndex == 1
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: _currentIndex == 1
                      ? AppColors.brown
                      : AppColors.darkGreen,
                ),
              ),
              selected: _currentIndex == 1,
              selectedTileColor: AppColors.peach.withValues(alpha: 0.35),
              onTap: () {
                _onTabSelected(1);
                Navigator.of(context).pop();
              },
            ),
            const Divider(color: AppColors.peach, thickness: 1),
            ListTile(
              leading: const Icon(
                Icons.settings_outlined,
                color: AppColors.darkGreen,
              ),
              title: Text(
                'Pengaturan',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.darkGreen,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      settingsRepository: widget.settingsRepository,
                      platformChannel: _platformChannel,
                      runExclusiveReset: _runtimeSync.runExclusiveReset,
                      onDataReset: () {
                        if (mounted) setState(() => _dataRevision++);
                      },
                    ),
                  ),
                );
                if (mounted) await _synchronize();
              },
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            if (_syncError != null || _isAccessibilityDisabled)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.4,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_syncError != null)
                        Material(
                          color: AppColors.peach,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Text(_syncError!)),
                                TextButton(
                                  onPressed: _isSynchronizing
                                      ? null
                                      : _synchronize,
                                  child: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_isAccessibilityDisabled)
                        RevokedPermissionBanner(
                          onFixPressed: _onFixAccessibilityPressed,
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  DashboardScreen(
                    refreshRevision: _dataRevision,
                    activityLogRepository: widget.activityLogRepository,
                    onNavigateToApplications: () => _onTabSelected(1),
                  ),
                  ApplicationSelectionScreen(
                    refreshRevision: _dataRevision,
                    blockedAppRepository: widget.blockedAppRepository,
                    platformChannel: _platformChannel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
        backgroundColor: AppColors.cream,
        selectedItemColor: AppColors.brown,
        unselectedItemColor: AppColors.darkGreenMuted,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.apps_outlined),
            activeIcon: Icon(Icons.apps),
            label: 'Aplikasi',
          ),
        ],
      ),
    );
  }
}
