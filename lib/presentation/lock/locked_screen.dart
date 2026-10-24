import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/blocked_app_repository.dart';
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
    this.autoOpenModal = true,
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
  final bool autoOpenModal;

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> with SingleTickerProviderStateMixin {
  late final SettingsRepository _settingsRepo;
  late final AnimationController _rotationController;

  Timer? _timer;
  int _remainingSeconds = 0;
  int _startEpoch = 0;
  int _endEpoch = 0;
  String _customMessage = 'Tetap fokus pada tujuanmu.';
  bool _modalTriggered = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _settingsRepo = widget.settingsRepository ?? SettingsRepositoryImpl();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _initScreen();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _initScreen() async {
    final message = await _settingsRepo.getCustomLockMessage();
    final now = DateTime.now().millisecondsSinceEpoch;

    _startEpoch = widget.startAtEpochMs ?? now;

    if (widget.endAtEpochMs != null) {
      _endEpoch = widget.endAtEpochMs!;
    } else {
      final waitingSeconds = await _settingsRepo.getWaitingDurationSeconds();
      _endEpoch = _startEpoch + (waitingSeconds * 1000);
    }

    if (mounted) {
      setState(() {
        _customMessage = message;
        _isLoading = false;
      });
      _tickTimer();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tickTimer());
    }
  }

  void _tickTimer() {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now < _startEpoch) {
      final totalSeconds = ((_endEpoch - _startEpoch) / 1000).ceil();
      setState(() {
        _remainingSeconds = totalSeconds > 0 ? totalSeconds : 300;
      });
      return;
    }

    final diffMs = _endEpoch - now;
    final seconds = (diffMs / 1000).ceil();

    if (seconds <= 0) {
      if (_remainingSeconds != 0) {
        setState(() => _remainingSeconds = 0);
      }
      _timer?.cancel();
      if (!_modalTriggered && widget.autoOpenModal) {
        _modalTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openPasswordUnlockModal();
        });
      }
    } else {
      setState(() {
        _remainingSeconds = seconds;
      });
    }
  }

  Future<void> _openPasswordUnlockModal() async {
    final unlocked = await PasswordUnlockModal.show(
      context,
      packageName: widget.packageName,
      appName: widget.appName,
      appId: widget.appId,
      settingsRepository: widget.settingsRepository,
      temporaryUnlockRepository: widget.temporaryUnlockRepository,
      activityLogRepository: widget.activityLogRepository,
      blockedAppRepository: widget.blockedAppRepository,
    );

    if (unlocked == true) {
      if (widget.onUnlocked != null) {
        widget.onUnlocked!();
      } else if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          SystemNavigator.pop();
        }
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
    final appDisplayName = widget.appName ??
        (widget.packageName != null ? widget.packageName! : 'Aplikasi Dibatasi');

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
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkGreen,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Aplikasi ini sedang dibatasi',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.darkGreenMuted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.peach.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '"$_customMessage"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            color: AppColors.darkGreen,
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      Text(
                        _formatTimer(_remainingSeconds),
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: AppColors.darkGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _remainingSeconds > 0
                          ? 'Tunggu hingga timer selesai untuk membuka akses'
                          : 'Waktu tunggu telah selesai',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.darkGreenMuted,
                        ),
                      ),
                      const Spacer(),
                      if (_remainingSeconds == 0)
                        AppButton(
                          text: 'Buka Kunci Aplikasi',
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
    );
  }
}
