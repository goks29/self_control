import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/platform/blocking_platform_channel.dart';
import '../../data/models/blocked_app.dart';
import '../../data/repositories/blocked_app_repository.dart';
import '../../data/repositories/blocked_app_repository_impl.dart';
import '../widgets/app_button.dart';
import 'widgets/permission_guide_modal.dart';

class ApplicationSelectionScreen extends StatefulWidget {
  const ApplicationSelectionScreen({
    super.key,
    this.blockedAppRepository,
    this.platformChannel,
  });

  final BlockedAppRepository? blockedAppRepository;
  final BlockingPlatformChannel? platformChannel;

  @override
  State<ApplicationSelectionScreen> createState() => _ApplicationSelectionScreenState();
}

class _ApplicationSelectionScreenState extends State<ApplicationSelectionScreen> {
  late final BlockedAppRepository _appRepo;
  late final BlockingPlatformChannel _platformChannel;

  List<BlockedApp> _apps = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isActivating = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _appRepo = widget.blockedAppRepository ?? BlockedAppRepositoryImpl();
    _platformChannel = widget.platformChannel ?? BlockingPlatformChannel();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    var loadedApps = List<BlockedApp>.from(await _appRepo.getAllApps());

    if (loadedApps.isEmpty) {
      final installed = await _platformChannel.getInstalledApps();
      if (installed.isNotEmpty) {
        final now = DateTime.now();
        final appsToSave = installed.map((app) {
          return BlockedApp(
            packageName: app['packageName'] as String,
            appName: app['appName'] as String,
            isSelected: false,
            createdAt: now,
          );
        }).toList();
        await _appRepo.saveApps(appsToSave);
        loadedApps = List<BlockedApp>.from(await _appRepo.getAllApps());
      }
    }

    loadedApps.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    if (mounted) {
      setState(() {
        _apps = loadedApps;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAppSelection(BlockedApp app) async {
    final newSelected = !app.isSelected;
    setState(() {
      final index = _apps.indexWhere((a) => a.packageName == app.packageName);
      if (index != -1) {
        _apps[index] = _apps[index].copyWith(isSelected: newSelected);
      }
    });

    await _appRepo.setAppSelected(app.packageName, newSelected);
  }

  Future<void> _toggleSelectAll() async {
    final allSelected = _apps.every((a) => a.isSelected);
    final targetState = !allSelected;

    setState(() {
      _apps = _apps.map((a) => a.copyWith(isSelected: targetState)).toList();
    });

    for (final app in _apps) {
      await _appRepo.setAppSelected(app.packageName, targetState);
    }
  }

  Future<void> _activateBlocking() async {
    setState(() => _isActivating = true);
    final status = await _platformChannel.getAccessibilityStatus();
    setState(() => _isActivating = false);

    if (status != 'enabled') {
      if (mounted) {
        await PermissionGuideModal.show(
          context,
          platformChannel: _platformChannel,
        );
      }
      return;
    }

    final selectedPackages = _apps
        .where((a) => a.isSelected)
        .map((a) => a.packageName)
        .toList();

    await _platformChannel.syncBlockedApps(selectedPackages);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pemblokiran aktif untuk ${selectedPackages.length} aplikasi'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brown),
      );
    }

    final filteredApps = _apps.where((app) {
      final q = _searchQuery.toLowerCase();
      return app.appName.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q);
    }).toList();

    final selectedCount = _apps.where((a) => a.isSelected).length;
    final allSelected = _apps.isNotEmpty && _apps.every((a) => a.isSelected);

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(
                color: AppColors.darkGreen,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Cari aplikasi...',
                prefixIcon: const Icon(Icons.search, color: AppColors.darkGreen),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.darkGreen),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$selectedCount aplikasi dipilih',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _apps.isEmpty ? null : _toggleSelectAll,
                  child: Text(
                    allSelected ? 'Batal Pilih Semua' : 'Pilih Semua',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brown,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.peach),
          Expanded(
            child: filteredApps.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'Tidak ada aplikasi terpasang'
                          : 'Aplikasi "$_searchQuery" tidak ditemukan',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.darkGreenMuted,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredApps.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: 72,
                      color: AppColors.peach,
                    ),
                    itemBuilder: (context, index) {
                      final app = filteredApps[index];
                      return ListTile(
                        onTap: () => _toggleAppSelection(app),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.peach,
                          foregroundColor: AppColors.darkGreen,
                          child: Text(
                            app.appName.isNotEmpty
                                ? app.appName.substring(0, 1).toUpperCase()
                                : '?',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(
                          app.appName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkGreen,
                          ),
                        ),
                        subtitle: Text(
                          app.packageName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.darkGreenMuted,
                          ),
                        ),
                        trailing: Checkbox(
                          value: app.isSelected,
                          onChanged: (_) => _toggleAppSelection(app),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.cream,
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow,
                  offset: Offset(0, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: AppButton(
                text: 'Aktifkan Pemblokiran',
                isLoading: _isActivating,
                onPressed: _activateBlocking,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
