import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../application/services/application_catalog_service.dart';
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
    this.refreshRevision = 0,
  });

  final BlockedAppRepository? blockedAppRepository;
  final BlockingPlatformChannel? platformChannel;
  final int refreshRevision;

  @override
  State<ApplicationSelectionScreen> createState() =>
      _ApplicationSelectionScreenState();
}

class _ApplicationSelectionScreenState
    extends State<ApplicationSelectionScreen> {
  late final BlockedAppRepository _appRepo;
  late final BlockingPlatformChannel _platformChannel;
  late final ApplicationCatalogService _catalog;

  List<BlockedApp> _apps = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isActivating = false;
  bool _isShowingPermissionGuide = false;
  bool _isSaving = false;
  bool _loadInProgress = false;
  bool _reloadPending = false;
  String? _error;

  bool get _isBusy => _loadInProgress || _isSaving || _isActivating;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _appRepo = widget.blockedAppRepository ?? BlockedAppRepositoryImpl();
    _platformChannel = widget.platformChannel ?? BlockingPlatformChannel();
    _catalog = ApplicationCatalogService(
      repository: _appRepo,
      platformChannel: _platformChannel,
    );
    _loadApps();
  }

  @override
  void didUpdateWidget(covariant ApplicationSelectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision) {
      _loadApps();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    if (!mounted) return;
    if (_isBusy) {
      _reloadPending = true;
      return;
    }
    _loadInProgress = true;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _catalog.loadApps();
      if (!mounted) return;
      setState(() {
        _apps = result.apps;
        _error = result.error == null
            ? null
            : 'Gagal memuat aplikasi terpasang. Daftar tersimpan ditampilkan.';
      });
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load application catalog',
        name: 'ApplicationSelectionScreen.loadApps',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = 'Gagal memuat daftar aplikasi.');
    } finally {
      _loadInProgress = false;
      if (mounted) {
        setState(() => _isLoading = false);
        _loadPendingRefresh();
      }
    }
  }

  void _loadPendingRefresh() {
    if (mounted && _reloadPending && !_isBusy) {
      _reloadPending = false;
      _loadApps();
    }
  }

  Future<void> _toggleAppSelection(BlockedApp app) =>
      _saveSelection([app], !app.isSelected);

  Future<void> _toggleSelectAll() =>
      _saveSelection(List.of(_apps), !_apps.every((app) => app.isSelected));

  Future<void> _saveSelection(List<BlockedApp> apps, bool selected) async {
    if (!mounted || _isBusy) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      // Commit each successful write to the UI, so a partial bulk failure
      // cannot leave the displayed selections ahead of persisted state.
      for (final app in apps) {
        if (!mounted) return;
        await _appRepo.setAppSelected(app.packageName, selected);
        if (!mounted) return;
        setState(() {
          _apps = _apps
              .map(
                (current) => current.packageName == app.packageName
                    ? current.copyWith(isSelected: selected)
                    : current,
              )
              .toList();
        });
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to persist application selection',
        name: 'ApplicationSelectionScreen.saveSelection',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = 'Gagal menyimpan pilihan aplikasi.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        _loadPendingRefresh();
      }
    }
  }

  Future<void> _activateBlocking() async {
    if (!mounted || _isBusy) return;
    setState(() {
      _isActivating = true;
      _error = null;
    });
    try {
      final activated = await _catalog.activateBlocking(_apps);
      if (!mounted) return;
      if (!activated) {
        setState(() => _isShowingPermissionGuide = true);
        await PermissionGuideModal.show(
          context,
          platformChannel: _platformChannel,
        );
        return;
      }
      final count = _apps.where((app) => app.isSelected).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pemblokiran aktif untuk $count aplikasi'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to activate application blocking',
        name: 'ApplicationSelectionScreen.activateBlocking',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = 'Gagal mengaktifkan pemblokiran. Coba lagi.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActivating = false;
          _isShowingPermissionGuide = false;
        });
        _loadPendingRefresh();
      }
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _isBusy ? null : _loadApps,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Cari aplikasi...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.darkGreen,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          color: AppColors.darkGreen,
                        ),
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
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Segarkan aplikasi',
                  onPressed: _isBusy ? null : _loadApps,
                  icon: const Icon(Icons.refresh, color: AppColors.darkGreen),
                ),
                TextButton(
                  onPressed: _apps.isEmpty || _isBusy ? null : _toggleSelectAll,
                  child: Text(
                    allSelected ? 'Batal Pilih Semua' : 'Pilih Semua',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: AppColors.brown),
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
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AppColors.darkGreenMuted),
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
                        onTap: _isBusy ? null : () => _toggleAppSelection(app),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.peach,
                          foregroundColor: AppColors.darkGreen,
                          child: Text(
                            app.appName.isNotEmpty
                                ? app.appName.substring(0, 1).toUpperCase()
                                : '?',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkGreen,
                                ),
                          ),
                        ),
                        title: Text(
                          app.appName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          app.packageName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Checkbox(
                          value: app.isSelected,
                          onChanged: _isBusy
                              ? null
                              : (_) => _toggleAppSelection(app),
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
                isLoading: _isActivating && !_isShowingPermissionGuide,
                onPressed: _isBusy ? null : _activateBlocking,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
