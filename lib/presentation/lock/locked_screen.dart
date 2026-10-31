import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/platform/blocking_platform_channel.dart';
import '../../data/models/activity_log.dart';
import '../../application/services/lock_session_service.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/activity_log_repository_impl.dart';
import '../../data/repositories/block_session_repository.dart';
import '../../data/repositories/blocked_app_repository.dart';
import '../../data/repositories/blocked_app_repository_impl.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/repositories/temporary_unlock_repository.dart';
import '../widgets/app_button.dart';
import 'widgets/password_unlock_modal.dart';

class LockedScreen extends StatefulWidget {
  const LockedScreen({
    super.key,
    this.packageName,
    this.appName,
    this.appId,
    this.startAtEpochMs,
    this.endAtEpochMs,
    this.onUnlocked,
    this.settingsRepository,
    this.temporaryUnlockRepository,
    this.activityLogRepository,
    this.blockedAppRepository,
    this.platformChannel,
    this.nowMsProvider,
    this.autoOpenModal = true,
    this.blockSessionRepository,
  });

  final String? packageName;
  final String? appName;
  final int? appId;
  final int? startAtEpochMs;
  final int? endAtEpochMs;
  final VoidCallback? onUnlocked;
  final SettingsRepository? settingsRepository;
  final TemporaryUnlockRepository? temporaryUnlockRepository;
  final ActivityLogRepository? activityLogRepository;
  final BlockedAppRepository? blockedAppRepository;
  final BlockingPlatformChannel? platformChannel;
  final int Function()? nowMsProvider;
  final bool autoOpenModal;
  final BlockSessionRepository? blockSessionRepository;

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final SettingsRepository _settingsRepo;
  late final BlockSessionRepository? _sessionRepo;
  late final BlockedAppRepository _blockedAppRepo;
  late final AnimationController _rotationController;

  final Stopwatch _monotonicStopwatch = Stopwatch();
  LockCountdownPolicy? _countdown;
  int _initializationGeneration = 0;
  String? _initializationError;
  String? _launchError;
  bool _modalOpen = false;
  bool _isLaunching = false;
  bool _accessGranted = false;

  Timer? _timer;
  int _remainingSeconds = 0;

  String _customMessage = 'Tetap fokus pada tujuanmu.';
  String? _resolvedAppName;
  int? _resolvedAppId;
  bool _modalTriggered = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsRepo = widget.settingsRepository ?? SettingsRepositoryImpl();
    _sessionRepo = widget.blockSessionRepository;
    _blockedAppRepo = widget.blockedAppRepository ?? BlockedAppRepositoryImpl();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _initScreen();
  }

  @override
  void didUpdateWidget(LockedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) {
      _timer?.cancel();
      _timer = null;
      _monotonicStopwatch.stop();
      _monotonicStopwatch.reset();
      setState(() {
        _isLoading = true;
        _modalTriggered = false;
        _remainingSeconds = 0;
        _countdown = null;
        _initializationError = null;
        _launchError = null;
        _accessGranted = false;
        _isLaunching = false;
        _resolvedAppName = null;
        _resolvedAppId = null;
      });
      _initScreen();
    }
  }

  @override
  void dispose() {
    _initializationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _monotonicStopwatch.stop();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tickTimer();
    }
  }

  int _getNow() =>
      widget.nowMsProvider?.call() ?? DateTime.now().millisecondsSinceEpoch;

  Future<void> _initScreen() async {
    final generation = ++_initializationGeneration;
    _timer?.cancel();
    _timer = null;
    _countdown = null;
    _monotonicStopwatch.stop();
    setState(() {
      _isLoading = true;
      _initializationError = null;
    });
    bool isCurrent() => mounted && generation == _initializationGeneration;
    try {
      final setup =
          await LockSessionService(
            settingsRepository: _settingsRepo,
            appRepository: _blockedAppRepo,
            sessionRepository: _sessionRepo,
          ).initialize(
            packageName: widget.packageName,
            appName: widget.appName,
            appId: widget.appId,
            startAtEpochMs: widget.startAtEpochMs,
            endAtEpochMs: widget.endAtEpochMs,
            nowMs: _getNow,
            isCancelled: () => !isCurrent(),
          );
      if (!isCurrent()) return;
      _countdown = LockCountdownPolicy(
        startEpochMs: setup.startEpochMs,
        endEpochMs: setup.endEpochMs,
        openedAtMs: setup.openedAtMs,
      );
      _monotonicStopwatch.reset();
      _monotonicStopwatch.start();
      setState(() {
        _customMessage = setup.message;
        _resolvedAppName = setup.appName;
        _resolvedAppId = setup.appId;
        _isLoading = false;
      });
      _tickTimer();
      if (_remainingSeconds > 0 && isCurrent()) {
        _timer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _tickTimer(),
        );
      }
    } catch (_) {
      if (!isCurrent()) return;
      setState(() {
        _initializationError =
            'Gagal memuat sesi pembatasan. Periksa penyimpanan lalu coba lagi.';
      });
    } finally {
      if (isCurrent()) setState(() => _isLoading = false);
    }
  }

  void _tickTimer() {
    final countdown = _countdown;
    if (!mounted || _isLoading || countdown == null || _accessGranted) return;
    final now = _getNow();
    final tick = countdown.tick(
      nowMs: now,
      monotonicElapsedMs: _monotonicStopwatch.elapsedMilliseconds,
    );
    if (tick.tamperingDetected) {
      _monotonicStopwatch.reset();
      _monotonicStopwatch.start();
      _logTampering(now);
    }
    if (_remainingSeconds != tick.remainingSeconds) {
      setState(() => _remainingSeconds = tick.remainingSeconds);
    }
    if (_remainingSeconds == 0) {
      _timer?.cancel();
      _timer = null;
      if (!_modalTriggered && widget.autoOpenModal) {
        _modalTriggered = true;
        final generation = _initializationGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _initializationGeneration) {
            _openPasswordUnlockModal();
          }
        });
      }
    }
  }

  Future<void> _logTampering(int timestampMs) async {
    final logRepo = widget.activityLogRepository ?? ActivityLogRepositoryImpl();
    try {
      await logRepo.logEvent(
        ActivityLog(
          appId: _resolvedAppId ?? widget.appId,
          packageNameSnapshot: widget.packageName ?? 'unknown.app',
          appNameSnapshot:
              _resolvedAppName ?? widget.appName ?? 'Aplikasi Dibatasi',
          eventType: ActivityLog.eventTamperingDetected,
          attemptedAt: DateTime.fromMillisecondsSinceEpoch(timestampMs),
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'tamper_audit_write_failed',
        name: 'self_control.lock',
        level: 900,
        error: error.runtimeType.toString(),
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _openPasswordUnlockModal() async {
    if (!mounted ||
        _modalOpen ||
        _isLoading ||
        _initializationError != null ||
        _remainingSeconds > 0) {
      return;
    }
    if (_accessGranted) {
      await _launchTargetApp();
      return;
    }
    _modalOpen = true;
    final generation = _initializationGeneration;
    try {
      final unlocked = await PasswordUnlockModal.show(
        context,
        packageName: widget.packageName,
        appName: _resolvedAppName ?? widget.appName,
        appId: _resolvedAppId ?? widget.appId,
        settingsRepository: widget.settingsRepository,
        temporaryUnlockRepository: widget.temporaryUnlockRepository,
        activityLogRepository: widget.activityLogRepository,
        blockedAppRepository: widget.blockedAppRepository,
        platformChannel: widget.platformChannel,
        blockSessionRepository: widget.blockSessionRepository,
      );

      if (!mounted || generation != _initializationGeneration) return;
      if (unlocked == true) {
        _timer?.cancel();
        _monotonicStopwatch.stop();
        setState(() => _accessGranted = true);
        await _launchTargetApp();
      }
    } finally {
      _modalOpen = false;
    }
  }

  Future<void> _launchTargetApp() async {
    if (!mounted || _isLaunching) return;
    final generation = _initializationGeneration;
    final package = widget.packageName;
    setState(() {
      _isLaunching = true;
      _launchError = null;
    });
    try {
      final channel = widget.platformChannel ?? BlockingPlatformChannel();
      final launched =
          package != null &&
          package.isNotEmpty &&
          await channel.launchTargetApp(package);
      if (!mounted || generation != _initializationGeneration) return;
      if (!launched) {
        setState(
          () => _launchError = 'Gagal membuka aplikasi. Akses sementara sudah aktif; coba lagi atau buka aplikasi secara manual.',
        );
        return;
      }
      if (widget.onUnlocked != null) {
        widget.onUnlocked!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        await SystemNavigator.pop();
      }
    } catch (_) {
      if (mounted && generation == _initializationGeneration) {
        setState(
          () => _launchError = 'Gagal membuka aplikasi. Coba lagi atau buka aplikasi secara manual.',
        );
      }
    } finally {
      if (mounted && generation == _initializationGeneration) {
        setState(() => _isLaunching = false);
      }
    }
  }

  String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final appDisplayName =
        _resolvedAppName ??
        widget.appName ??
        (widget.packageName != null
            ? widget.packageName!
            : 'Aplikasi Dibatasi');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.brown),
                )
              : _initializationError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _initializationError!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        AppButton(text: 'Coba Lagi', onPressed: _initScreen),
                        const SizedBox(height: 16),
                        AppButton(
                          text: 'Kembali ke Layar Utama',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => SystemNavigator.pop(),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ),
                          child: Column(
                            children: [
                              const Spacer(),
                              RotationTransition(
                                turns: _rotationController,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: const BoxDecoration(
                                    color: AppColors.peach,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.hourglass_bottom_rounded,
                                    size: 52,
                                    color: AppColors.brown,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                appDisplayName,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Aplikasi ini sedang dibatasi',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.darkGreenMuted),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.peach.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '"$_customMessage"',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 36),
                              Text(
                                _formatTimer(_remainingSeconds),
                                style: Theme.of(context).textTheme.displayLarge
                                    ?.copyWith(
                                      fontSize: 56,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _remainingSeconds > 0
                                    ? 'Tunggu hingga timer selesai untuk membuka akses'
                                    : 'Waktu tunggu telah selesai',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const Spacer(),
                              if (_launchError != null) ...[
                                Text(
                                  _launchError!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_remainingSeconds == 0)
                                AppButton(
                                  text: _accessGranted
                                      ? 'Coba Buka Aplikasi Lagi'
                                      : 'Buka Kunci Aplikasi',
                                  isLoading: _isLaunching,
                                  onPressed: _openPasswordUnlockModal,
                                ),
                              const SizedBox(height: 16),
                              AppButton(
                                text: 'Kembali ke Layar Utama',
                                variant: AppButtonVariant.secondary,
                                onPressed: () => SystemNavigator.pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
