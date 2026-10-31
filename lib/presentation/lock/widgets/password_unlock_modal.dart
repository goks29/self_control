import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/platform/blocking_platform_channel.dart';
import '../../../application/services/temporary_unlock_service.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/activity_log_repository_impl.dart';
import '../../../data/repositories/block_session_repository.dart';
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
    this.platformChannel,
    this.initialDurationSeconds,
    this.blockSessionRepository,
  });

  final String? packageName;
  final String? appName;
  final int? appId;
  final SettingsRepository? settingsRepository;
  final TemporaryUnlockRepository? temporaryUnlockRepository;
  final ActivityLogRepository? activityLogRepository;
  final BlockedAppRepository? blockedAppRepository;
  final BlockingPlatformChannel? platformChannel;
  final int? initialDurationSeconds;
  final BlockSessionRepository? blockSessionRepository;

  static Future<bool?> show(
    BuildContext context, {
    String? packageName,
    String? appName,
    int? appId,
    SettingsRepository? settingsRepository,
    TemporaryUnlockRepository? temporaryUnlockRepository,
    ActivityLogRepository? activityLogRepository,
    BlockedAppRepository? blockedAppRepository,
    BlockingPlatformChannel? platformChannel,
    int? initialDurationSeconds,
    BlockSessionRepository? blockSessionRepository,
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
          platformChannel: platformChannel,
          initialDurationSeconds: initialDurationSeconds,
          blockSessionRepository: blockSessionRepository,
        ),
      ),
    );
  }

  @override
  State<PasswordUnlockModal> createState() => _PasswordUnlockModalState();
}

class _PasswordUnlockModalState extends State<PasswordUnlockModal> {
  late final SettingsRepository _settingsRepo;
  late final TemporaryUnlockService _unlockService;
  bool _durationChanged = false;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _customMinutesController = TextEditingController(
    text: '10',
  );

  bool _obscurePassword = true;
  String? _errorMessage;
  bool _isSubmitting = false;
  bool _unlockCompleted = false;

  int _selectedDurationSeconds = 600;
  bool _isCustomDuration = false;

  @override
  void initState() {
    super.initState();
    _settingsRepo = widget.settingsRepository ?? SettingsRepositoryImpl();
    _unlockService = TemporaryUnlockService(
      settingsRepository: _settingsRepo,
      unlockRepository:
          widget.temporaryUnlockRepository ?? TemporaryUnlockRepositoryImpl(),
      logRepository:
          widget.activityLogRepository ?? ActivityLogRepositoryImpl(),
      appRepository: widget.blockedAppRepository ?? BlockedAppRepositoryImpl(),
      sessionRepository: widget.blockSessionRepository,
      platformChannel: widget.platformChannel ?? BlockingPlatformChannel(),
    );

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
    try {
      final defaultDuration = await _settingsRepo
          .getDefaultUnlockDurationSeconds();
      if (mounted &&
          !_durationChanged &&
          !_isSubmitting &&
          defaultDuration > 0) {
        setState(() => _selectedDurationSeconds = defaultDuration);
      }
    } catch (_) {
      // The visible 10-minute default remains usable when settings cannot load.
    }
  }

  Future<void> _submitUnlock() async {
    if (_isSubmitting || _unlockCompleted || !mounted) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Masukkan password');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final durationSeconds = _isCustomDuration
        ? (int.tryParse(_customMinutesController.text.trim()) ?? 10).clamp(
                1,
                180,
              ) *
              60
        : _selectedDurationSeconds;
    try {
      final warning = await _unlockService.unlock(
        password: password,
        packageName: widget.packageName,
        appName: widget.appName,
        appId: widget.appId,
        durationSeconds: durationSeconds,
        isCancelled: () => !mounted,
      );
      if (!mounted) return;
      _unlockCompleted = true;
      if (warning != null) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(warning)));
      }
      Navigator.of(context).pop(true);
    } on TemporaryUnlockException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Gagal membuka akses. Periksa penyimpanan dan layanan aksesibilitas lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: AppSpacing.sheetPadding,
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.xxl),
        ),
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
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Buka Akses Sementara', style: textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Waktu tunggu selesai. Masukkan password Anda untuk membuka akses sementara.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.darkGreenMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
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
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Durasi Buka Akses',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  _buildDurationChip(300, '5 menit'),
                  _buildDurationChip(600, '10 menit'),
                  _buildDurationChip(900, '15 menit'),
                  ChoiceChip(
                    label: const Text('Kustom'),
                    selected: _isCustomDuration,
                    onSelected: _isSubmitting
                        ? null
                        : (selected) {
                            setState(() {
                              _durationChanged = true;
                              _isCustomDuration = selected;
                            });
                          },
                  ),
                ],
              ),
              if (_isCustomDuration) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Menit Kustom (1-180)',
                  hint: 'Contoh: 20',
                  controller: _customMinutesController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
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
    final isSelected =
        !_isCustomDuration && _selectedDurationSeconds == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: _isSubmitting
          ? null
          : (selected) {
              if (selected) {
                setState(() {
                  _durationChanged = true;
                  _selectedDurationSeconds = seconds;
                  _isCustomDuration = false;
                });
              }
            },
    );
  }
}
