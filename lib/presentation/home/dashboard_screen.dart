import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/activity_log.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/activity_log_repository_impl.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.activityLogRepository,
    this.onNavigateToApplications,
  });

  final ActivityLogRepository? activityLogRepository;
  final VoidCallback? onNavigateToApplications;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ActivityLogRepository _logRepo;
  bool _isLoading = true;
  Map<String, int> _attemptCounts = {};
  Map<String, String> _appNames = {};
  Map<String, DateTime> _lastAttempts = {};
  int _failedBlocksCount = 0;

  @override
  void initState() {
    super.initState();
    _logRepo = widget.activityLogRepository ?? ActivityLogRepositoryImpl();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final counts = await _logRepo.getAttemptCountsByPackage(outcome: ActivityLog.outcomeConfirmed);
    final outcomeCounts = await _logRepo.getOutcomeCounts();
    final logs = await _logRepo.getLogs(limit: 100);

    final appNames = <String, String>{};
    final lastAttempts = <String, DateTime>{};

    for (final log in logs) {
      if (!appNames.containsKey(log.packageNameSnapshot)) {
        appNames[log.packageNameSnapshot] = log.appNameSnapshot;
      }
      if (!lastAttempts.containsKey(log.packageNameSnapshot)) {
        lastAttempts[log.packageNameSnapshot] = log.attemptedAt;
      }
    }

    if (mounted) {
      setState(() {
        _attemptCounts = counts;
        _appNames = appNames;
        _lastAttempts = lastAttempts;
        _failedBlocksCount = outcomeCounts[ActivityLog.outcomeFailed] ?? 0;
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Baru saja';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} menit lalu';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} jam lalu';
    } else {
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.brown),
        ),
      );
    }

    final totalAttempts = _attemptCounts.values.fold<int>(0, (sum, val) => sum + val);

    if (_attemptCounts.isEmpty || totalAttempts == 0) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        body: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.brown,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            children: [
              const SizedBox(height: 48),
              Center(
                child: Icon(
                  Icons.shield_outlined,
                  size: 80,
                  color: AppColors.darkGreen.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Belum Ada Aktivitas Blokir',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Belum ada aktivitas percobaan membuka aplikasi. Pilih aplikasi yang ingin dibatasi di tab Aplikasi untuk mulai melindungi fokus Anda.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 32),
              if (widget.onNavigateToApplications != null)
                Center(
                  child: AppButton(
                    text: 'Pilih Aplikasi',
                    isFullWidth: false,
                    onPressed: widget.onNavigateToApplications,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final sortedPackages = _attemptCounts.keys.toList()
      ..sort((a, b) => (_attemptCounts[b] ?? 0).compareTo(_attemptCounts[a] ?? 0));

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.brown,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Percobaan Dicegah',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalAttempts',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Akses aplikasi terlarang berhasil diblokir.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.darkGreenMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (_failedBlocksCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.peach,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.brown.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.brown,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$_failedBlocksCount percobaan blokir memerlukan izin pembuka latar belakang.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.darkGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Aplikasi Terbanyak Diblokir',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.peach,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${sortedPackages.length} aplikasi',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sortedPackages.map((pkg) {
              final count = _attemptCounts[pkg] ?? 0;
              final name = _appNames[pkg] ?? pkg;
              final lastTime = _lastAttempts[pkg];

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.darkGreen,
                        foregroundColor: AppColors.peach,
                        child: Text(
                          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkGreen,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              lastTime != null
                                  ? '$pkg • ${_formatDateTime(lastTime)}'
                                  : pkg,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.darkGreenMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.brown,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '$count kali',
                          style: const TextStyle(
                            color: AppColors.cream,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
