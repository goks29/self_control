import 'package:flutter/material.dart';

import '../../application/services/database_maintenance_service.dart';
import '../../application/services/settings_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/platform/blocking_platform_channel.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.settingsRepository,
    this.appDatabase,
    this.platformChannel,
    this.onDataReset,
    this.runExclusiveReset,
  });

  final SettingsRepository? settingsRepository;
  final AppDatabase? appDatabase;
  final BlockingPlatformChannel? platformChannel;
  final VoidCallback? onDataReset;

  /// Lets the application shell stop background synchronization while the
  /// database is recreated.
  final Future<T> Function<T>(Future<T> Function() reset)? runExclusiveReset;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsService _settingsService;
  late final DatabaseMaintenanceService _maintenanceService;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isChecking = false;
  bool _isResetting = false;
  bool _hasExistingPassword = false;
  String? _loadError;

  bool get _isBusy => _isLoading || _isSaving || _isChecking || _isResetting;

  int _waitingDurationSeconds = 300;
  int _defaultUnlockDurationSeconds = 600;

  final TextEditingController _customMessageController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final database = widget.appDatabase ?? AppDatabase.instance;
    _settingsService = SettingsService(
      repository:
          widget.settingsRepository ??
          SettingsRepositoryImpl(appDatabase: database),
    );
    _maintenanceService = DatabaseMaintenanceService(
      database: database,
      channel: widget.platformChannel ?? BlockingPlatformChannel(),
    );
    _loadSettings();
  }

  @override
  void dispose() {
    _customMessageController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<bool> _loadSettings() async {
    if (!mounted) return false;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final settings = await _settingsService.load();
      if (!mounted) return false;
      setState(() {
        _waitingDurationSeconds = settings.waitingDurationSeconds;
        _customMessageController.text = settings.customLockMessage;
        _defaultUnlockDurationSeconds = settings.defaultUnlockDurationSeconds;
        _hasExistingPassword = settings.hasExistingPassword;
      });
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = 'Gagal memuat pengaturan: $e');
      }
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.brown : AppColors.darkGreen,
        ),
      );
  }

  Future<void> _saveSettings() async {
    if (!mounted || _isBusy || _loadError != null) return;
    final waitingDuration = _waitingDurationSeconds;
    final message = _customMessageController.text;
    final unlockDuration = _defaultUnlockDurationSeconds;
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() => _passwordError = null);

    if (password.isNotEmpty) {
      if (password.length < 4) {
        setState(() => _passwordError = 'Password minimal 4 karakter');
        return;
      }
      if (password != confirmPassword) {
        setState(() => _passwordError = 'Konfirmasi password tidak cocok');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      await _settingsService.save(
        waitingDurationSeconds: waitingDuration,
        customLockMessage: message,
        defaultUnlockDurationSeconds: unlockDuration,
        password: password,
      );
      if (!mounted) return;
      if (password.isNotEmpty) {
        // Do not erase edits made while the save was pending.
        if (_passwordController.text == password) _passwordController.clear();
        if (_confirmPasswordController.text == confirmPassword) {
          _confirmPasswordController.clear();
        }
        setState(() => _hasExistingPassword = true);
      }
      _showMessage('Pengaturan berhasil disimpan.');
    } catch (e) {
      _showMessage('Gagal menyimpan pengaturan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _checkIntegrity() async {
    if (!mounted || _isBusy) return;
    setState(() => _isChecking = true);
    try {
      final result = await _maintenanceService.verifyIntegrity(full: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      if (result.isHealthy) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Basis data sehat. Tidak ditemukan kerusakan atau pelanggaran relasi.',
            ),
            backgroundColor: AppColors.darkGreen,
          ),
        );
      } else {
        final msg = result.integrityErrors.isNotEmpty
            ? result.integrityErrors.join(', ')
            : 'Ditemukan ${result.foreignKeyViolations.length} pelanggaran relasi.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Peringatan: $msg'),
            backgroundColor: AppColors.brown,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memeriksa integritas: $e'),
          backgroundColor: AppColors.brown,
        ),
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _confirmReset() async {
    if (!mounted || _isBusy) return;
    setState(() => _isResetting = true);
    void dismissDialog(BuildContext dialogContext, bool confirmed) {
      if (!dialogContext.mounted ||
          ModalRoute.of(dialogContext)?.isCurrent != true) {
        return;
      }
      Navigator.of(dialogContext).pop(confirmed);
    }

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cream,
          title: Text(
            'Konfirmasi Reset',
            style: Theme.of(ctx).textTheme.headlineSmall,
          ),
          content: Text(
            'Tindakan ini akan mengembalikan seluruh pengaturan ke bawaan dan menghapus riwayat blokir. Lanjutkan?',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => dismissDialog(ctx, false),
              child: Text(
                'Batal',
                style: Theme.of(ctx).textTheme.labelLarge
                    ?.copyWith(color: AppColors.darkGreen),
              ),
            ),
            AppButton(
              text: 'Reset',
              isFullWidth: false,
              onPressed: () => dismissDialog(ctx, true),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;
      final onDataReset = widget.onDataReset;
      final exclusiveReset = widget.runExclusiveReset;
      if (exclusiveReset == null) {
        await _maintenanceService.resetToDefaults();
      } else {
        await exclusiveReset(_maintenanceService.resetToDefaults);
      }
      // The reset has committed, even if this screen was removed or reload fails.
      onDataReset?.call();
      if (!mounted) return;
      _passwordController.clear();
      _confirmPasswordController.clear();
      setState(() => _passwordError = null);
      final loaded = await _loadSettings();
      if (loaded) _showMessage('Seluruh pengaturan dan data berhasil direset.');
    } catch (e) {
      _showMessage('Gagal mereset data: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pengaturan')),
        backgroundColor: AppColors.cream,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.brown),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pengaturan')),
        backgroundColor: AppColors.cream,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!),
                const SizedBox(height: 16),
                AppButton(
                  text: 'Coba Lagi',
                  onPressed: _isBusy ? null : _loadSettings,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      backgroundColor: AppColors.cream,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Durasi Tunggu Layar Kunci'),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waktu tunggu sebelum opsi memasukkan password tersedia di layar kunci.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildDurationChip(60, '1 menit'),
                    _buildDurationChip(180, '3 menit'),
                    _buildDurationChip(300, '5 menit'),
                    _buildDurationChip(600, '10 menit'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader('Pesan Kunci Layar'),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pesan motivasi yang ditampilkan saat layar terkunci.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _customMessageController,
                  maxLines: 3,
                  maxLength: 100,
                  hint: 'Tetap fokus pada tujuanmu.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader('Durasi Buka Akses Bawaan'),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Durasi bawaan saat membuka akses aplikasi sementara.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildUnlockChip(300, '5 menit'),
                    _buildUnlockChip(600, '10 menit'),
                    _buildUnlockChip(900, '15 menit'),
                    _buildUnlockChip(1800, '30 menit'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader('Keamanan Password'),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hasExistingPassword)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: AppColors.brown,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Password sudah diatur',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.brown,
                              ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  _hasExistingPassword
                      ? 'Kosongkan jika tidak ingin mengubah password.'
                      : 'Atur password untuk membuka akses aplikasi setelah waktu tunggu selesai.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Password Baru',
                  hint: 'Minimal 4 karakter',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  errorText: _passwordError,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.darkGreen,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Konfirmasi Password',
                  hint: 'Ulangi password baru',
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.darkGreen,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          AppButton(
            text: 'Simpan Pengaturan',
            isLoading: _isSaving,
            onPressed: _isBusy ? null : _saveSettings,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Pemulihan & Integritas Data'),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Periksa kesehatan basis data lokal atau lakukan pemulihan jika terjadi kegagalan sistem.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Cek Integritas',
                        variant: AppButtonVariant.secondary,
                        height: 48.0,
                        isLoading: _isChecking,
                        onPressed: _isBusy ? null : _checkIntegrity,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        text: 'Reset Darurat',
                        variant: AppButtonVariant.outlineBrown,
                        height: 48.0,
                        onPressed: _isBusy ? null : _confirmReset,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildDurationChip(int seconds, String label) {
    final isSelected = _waitingDurationSeconds == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _waitingDurationSeconds = seconds);
        }
      },
    );
  }

  Widget _buildUnlockChip(int seconds, String label) {
    final isSelected = _defaultUnlockDurationSeconds == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _defaultUnlockDurationSeconds = seconds);
        }
      },
    );
  }
}
