import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/activity_log.dart';
import '../../data/models/focus_task.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/activity_log_repository_impl.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/task_repository_impl.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.activityLogRepository,
    this.taskRepository,
    this.onNavigateToApplications,
    this.refreshRevision = 0,
  });

  final ActivityLogRepository? activityLogRepository;
  final TaskRepository? taskRepository;
  final VoidCallback? onNavigateToApplications;
  final int refreshRevision;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ActivityLogRepository _logRepo;
  late final TaskRepository _taskRepo;
  final TextEditingController _taskController = TextEditingController();

  bool _isLoading = true;
  Map<String, int> _attemptCounts = {};
  Map<String, String> _appNames = {};
  Map<String, DateTime> _lastAttempts = {};
  List<FocusTask> _tasks = [];
  int _failedBlocksCount = 0;
  int _loadRevision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _logRepo = widget.activityLogRepository ?? ActivityLogRepositoryImpl();
    _taskRepo = widget.taskRepository ?? TaskRepositoryImpl();
    _loadData();
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final revision = ++_loadRevision;
    bool isCurrent() => mounted && revision == _loadRevision;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final counts = await _logRepo.getAttemptCountsByPackage(
        outcome: ActivityLog.outcomeConfirmed,
      );
      if (!isCurrent()) return;
      final outcomeCounts = await _logRepo.getOutcomeCounts();
      if (!isCurrent()) return;
      final logs = await _logRepo.getLogs(limit: 100);
      if (!isCurrent()) return;

      List<FocusTask> loadedTasks = [];
      try {
        loadedTasks = await _taskRepo.getAllTasks();
      } catch (_) {
        loadedTasks = [];
      }
      if (!isCurrent()) return;

      final appNames = <String, String>{};
      final lastAttempts = <String, DateTime>{};
      for (final log in logs) {
        appNames.putIfAbsent(
          log.packageNameSnapshot,
          () => log.appNameSnapshot,
        );
        lastAttempts.putIfAbsent(
          log.packageNameSnapshot,
          () => log.attemptedAt,
        );
      }
      setState(() {
        _attemptCounts = counts;
        _appNames = appNames;
        _lastAttempts = lastAttempts;
        _tasks = loadedTasks;
        _failedBlocksCount = outcomeCounts[ActivityLog.outcomeFailed] ?? 0;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load dashboard activity (revision $revision)',
        name: 'DashboardScreen.loadData',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (isCurrent()) {
        setState(() => _error = 'Gagal memuat aktivitas blokir.');
      }
    } finally {
      if (isCurrent()) setState(() => _isLoading = false);
    }
  }

  Future<void> _addTask() async {
    final text = _taskController.text.trim();
    if (text.isEmpty) return;
    try {
      await _taskRepo.addTask(text);
      _taskController.clear();
      final updated = await _taskRepo.getAllTasks();
      if (mounted) {
        setState(() => _tasks = updated);
      }
    } catch (_) {}
  }

  Future<void> _toggleTask(FocusTask task) async {
    if (task.id == null) return;
    try {
      await _taskRepo.toggleTaskCompletion(task.id!, !task.isCompleted);
      final updated = await _taskRepo.getAllTasks();
      if (mounted) {
        setState(() => _tasks = updated);
      }
    } catch (_) {}
  }

  Future<void> _deleteTask(FocusTask task) async {
    if (task.id == null) return;
    try {
      await _taskRepo.deleteTask(task.id!);
      final updated = await _taskRepo.getAllTasks();
      if (mounted) {
        setState(() => _tasks = updated);
      }
    } catch (_) {}
  }

  Widget _buildTaskSection(BuildContext context) {
    final pendingCount = _tasks.where((t) => !t.isCompleted).length;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Daftar Tugas Fokus',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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
                  '$pendingCount belum selesai',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tugas yang belum selesai akan ditampilkan saat Anda menunggu timer layar kunci.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  hint: 'Tambah tugas yang harus dikerjakan...',
                  controller: _taskController,
                  onFieldSubmitted: (_) => _addTask(),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                text: 'Tambah',
                isFullWidth: false,
                onPressed: _addTask,
              ),
            ],
          ),
          if (_tasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: task.isCompleted,
                      activeColor: AppColors.brown,
                      onChanged: (_) => _toggleTask(task),
                    ),
                    Expanded(
                      child: Text(
                        task.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? AppColors.darkGreenMuted
                              : AppColors.darkGreen,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.brown,
                        size: 20,
                      ),
                      tooltip: 'Hapus Tugas',
                      onPressed: () => _deleteTask(task),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
        body: Center(child: CircularProgressIndicator(color: AppColors.brown)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                AppButton(
                  text: 'Coba Lagi',
                  isFullWidth: false,
                  onPressed: _loadData,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalAttempts = _attemptCounts.values.fold<int>(
      0,
      (sum, val) => sum + val,
    );

    if (_attemptCounts.isEmpty || totalAttempts == 0) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        body: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.brown,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            children: [
              _buildTaskSection(context),
              const SizedBox(height: 32),
              Center(
                child: Icon(
                  Icons.shield_outlined,
                  size: 80,
                  color: AppColors.darkGreen.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Belum Ada Aktivitas Blokir',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Belum ada aktivitas percobaan membuka aplikasi. Pilih aplikasi yang ingin dibatasi di tab Aplikasi untuk mulai melindungi fokus Anda.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(height: 1.5),
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
      ..sort(
        (a, b) => (_attemptCounts[b] ?? 0).compareTo(_attemptCounts[a] ?? 0),
      );

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.brown,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildTaskSection(context),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Percobaan Dicegah',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalAttempts',
                    style: Theme.of(context).textTheme.displayLarge
                        ?.copyWith(fontSize: 40, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Akses aplikasi terlarang berhasil diblokir.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (_failedBlocksCount > 0) ...[
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: Border.all(
                  color: AppColors.brown.withValues(alpha: 0.3),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                Expanded(
                  child: Text(
                    'Aplikasi Terbanyak Diblokir',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.peach,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${sortedPackages.length} aplikasi',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
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

              return AppCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.darkGreen,
                      foregroundColor: AppColors.peach,
                      child: Text(
                        name.isNotEmpty
                            ? name.substring(0, 1).toUpperCase()
                            : '?',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.peach,
                            ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastTime != null
                                ? '$pkg • ${_formatDateTime(lastTime)}'
                                : pkg,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brown,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '$count kali',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.cream,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
