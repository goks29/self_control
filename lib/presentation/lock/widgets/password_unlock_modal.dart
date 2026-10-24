import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/activity_log.dart';
import '../../../data/models/temporary_unlock.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/activity_log_repository_impl.dart';
import '../../../data/repositories/blocked_app_repository.dart';
import '../../../data/repositories/blocked_app_repository_impl.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/settings_repository_impl.dart';
import '../../../data/repositories/temporary_unlock_repository.dart';
import '../../../data/repositories/temporary_unlock_repository_impl.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class PasswordUnlockModal extends StatefulWidget {
  const PasswordUnlockModal({
    super.key,
    this.packageName,
    this.appName,
    this.appId,
    this.settingsRepository,
    this.temporaryUnlockRepository,
    this.activityLogRepository,
    this.blockedAppRepository,
    this.initialDurationSeconds,
  });

  final String? packageName;
  final String? appName;
  final int? appId;
  final SettingsRepository? settingsRepository;
  final TemporaryUnlockRepository? temporaryUnlockRepository;
  final ActivityLogRepository? activityLogRepository;
  final BlockedAppRepository? blockedAppRepository;
  final int? initialDurationSeconds;

  static Future<bool?> show(
    BuildContext context, {
    String? packageName,
    String? appName,
    int? appId,
    SettingsRepository? settingsRepository,
    TemporaryUnlockRepository? temporaryUnlockRepository,
    ActivityLogRepository? activityLogRepository,
    BlockedAppRepository? blockedAppRepository,
    int? initialDurationSeconds,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: PasswordUnlockModal(
          packageName: packageName,
          appName: appName,
          appId: appId,
          settingsRepository: settingsRepository,
          temporaryUnlockRepository: temporaryUnlockRepository,
          activityLogRepository: activityLogRepository,
          blockedAppRepository: blockedAppRepository,
          initialDurationSeconds: initialDurationSeconds,
        ),
      ),
    );
  }

  @override
  State<PasswordUnlockModal> createState() => _PasswordUnlockModalState();
}

class _PasswordUnlockModalState extends State<PasswordUnlockModal> {
  late final SettingsRepository _settingsRepo;
  late final TemporaryUnlockRepository _unlockRepo;
  late final ActivityLogRepository _logRepo;
  late final BlockedAppRepository _appRepo;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _customMinutesController = TextEditingController(text: '10');

  bool _obscurePassword = true;
  String? _errorMessage;
  bool _isSubmitting = false;

  int _selectedDurationSeconds = 600;
  bool _isCustomDuration = false;

  @override
  void initState() {
    super.initState();
    _settingsRepo = widget.settingsRepository ?? SettingsRepositoryImpl();
    _unlockRepo = widget.temporaryUnlockRepository ?? TemporaryUnlockRepositoryImpl();
    _logRepo = widget.activityLogRepository ?? ActivityLogRepositoryImpl();
    _appRepo = widget.blockedAppRepository ?? BlockedAppRepositoryImpl();

    if (widget.initialDurationSeconds != null) {
      _selectedDurationSeconds = widget.initialDurationSeconds!;
    } else {
      _loadDefaultDuration();
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _customMinutesController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultDuration() async {
    final defaultDuration = await _settingsRepo.getDefaultUnlockDurationSeconds();
    if (mounted) {
      setState(() {
        _selectedDurationSeconds = defaultDuration;
      });
    }
  }

  Future<void> _submitUnlock() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Masukkan password');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final isValid = await _settingsRepo.verifyPassword(password);
    final packageName = widget.packageName ?? 'unknown.app';
    final appName = widget.appName ?? 'Aplikasi';

    if (!isValid) {
      await _logRepo.logEvent(
        ActivityLog(
          appId: widget.appId,
          packageNameSnapshot: packageName,
          appNameSnapshot: appName,
          eventType: ActivityLog.eventPasswordFailed,
          attemptedAt: DateTime.now(),
        ),
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Password salah. Silakan coba lagi.';
        });
      }
      return;
    }

    int durationSeconds = _selectedDurationSeconds;
    if (_isCustomDuration) {
      final customMinutes = int.tryParse(_customMinutesController.text.trim()) ?? 10;
      final clampedMinutes = customMinutes.clamp(1, 180);
      durationSeconds = clampedMinutes * 60;
    }

    int effectiveAppId = widget.appId ?? 0;
    if (effectiveAppId <= 0 && widget.packageName != null) {
      final app = await _appRepo.getAppByPackageName(widget.packageName!);
      if (app?.id != null) {
        effectiveAppId = app!.id!;
      }
    }

    final now = DateTime.now();
    final endAt = now.add(Duration(seconds: durationSeconds));

    if (effectiveAppId > 0) {
      await _unlockRepo.createUnlock(
        TemporaryUnlock(
          appId: effectiveAppId,
          startAt: now,
          endAt: endAt,
          status: TemporaryUnlock.statusActive,
          createdAt: now,
        ),
      );
    }

    await _logRepo.logEvent(
      ActivityLog(
        appId: effectiveAppId > 0 ? effectiveAppId : null,
        packageNameSnapshot: packageName,
        appNameSnapshot: appName,
        eventType: ActivityLog.eventTemporaryUnlockStarted,
        attemptedAt: now,
      ),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.peach,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Buka Akses Sementara',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Waktu tunggu selesai. Masukkan password Anda untuk membuka akses sementara.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.darkGreenMuted,
                ),
              ),
              const SizedBox(height: 20),
              AppTextField(
                label: 'Password',
                hint: 'Masukkan password Anda',
                controller: _passwordController,
                obscureText: _obscurePassword,
                errorText: _errorMessage,
                autofocus: true,
                onFieldSubmitted: (_) => _submitUnlock(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.darkGreen,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Durasi Buka Akses',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildDurationChip(300, '5 menit'),
                  _buildDurationChip(600, '10 menit'),
                  _buildDurationChip(900, '15 menit'),
                  ChoiceChip(
                    label: const Text('Kustom'),
                    selected: _isCustomDuration,
                    onSelected: (selected) {
                      setState(() {
                        _isCustomDuration = selected;
                      });
                    },
                  ),
                ],
              ),
              if (_isCustomDuration) ...[
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Menit Kustom (1-180)',
                  hint: 'Contoh: 20',
                  controller: _customMinutesController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
              const SizedBox(height: 24),
              AppButton(
                text: 'Buka Sementara',
                isLoading: _isSubmitting,
                onPressed: _submitUnlock,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationChip(int seconds, String label) {
    final isSelected = !_isCustomDuration && _selectedDurationSeconds == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedDurationSeconds = seconds;
            _isCustomDuration = false;
          });
        }
      },
    );
  }
}
