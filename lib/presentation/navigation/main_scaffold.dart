import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/platform/blocking_platform_channel.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/blocked_app_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../application/application_selection_screen.dart';
import '../home/dashboard_screen.dart';
import '../settings/settings_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({
    super.key,
    this.activityLogRepository,
    this.blockedAppRepository,
    this.platformChannel,
    this.settingsRepository,
    this.initialIndex = 0,
  });

  final ActivityLogRepository? activityLogRepository;
  final BlockedAppRepository? blockedAppRepository;
  final BlockingPlatformChannel? platformChannel;
  final SettingsRepository? settingsRepository;
  final int initialIndex;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
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
              decoration: const BoxDecoration(
                color: AppColors.darkGreen,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
                  Text(
                    'Self-Control',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cream,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Fokus & Disiplin Digital',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.peach,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                _currentIndex == 0 ? Icons.dashboard : Icons.dashboard_outlined,
                color: _currentIndex == 0 ? AppColors.brown : AppColors.darkGreen,
              ),
              title: Text(
                'Beranda',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: _currentIndex == 0 ? FontWeight.w700 : FontWeight.w500,
                  color: _currentIndex == 0 ? AppColors.brown : AppColors.darkGreen,
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
                color: _currentIndex == 1 ? AppColors.brown : AppColors.darkGreen,
              ),
              title: Text(
                'Aplikasi',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: _currentIndex == 1 ? FontWeight.w700 : FontWeight.w500,
                  color: _currentIndex == 1 ? AppColors.brown : AppColors.darkGreen,
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
              title: const Text(
                'Pengaturan',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.darkGreen,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      settingsRepository: widget.settingsRepository,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(
            activityLogRepository: widget.activityLogRepository,
            onNavigateToApplications: () => _onTabSelected(1),
          ),
          ApplicationSelectionScreen(
            blockedAppRepository: widget.blockedAppRepository,
            platformChannel: widget.platformChannel,
          ),
        ],
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
