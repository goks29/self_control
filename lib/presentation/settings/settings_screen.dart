import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_text_field.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.settingsRepository,
  });

  final SettingsRepository? settingsRepository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsRepository _settingsRepo;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasExistingPassword = false;

  int _waitingDurationSeconds = 300;
  int _defaultUnlockDurationSeconds = 600;

  final TextEditingController _customMessageController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _settingsRepo = widget.settingsRepository ?? SettingsRepositoryImpl();
    _loadSettings();
  }

  @override
  void dispose() {
    _customMessageController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final waitingDuration = await _settingsRepo.getWaitingDurationSeconds();
    final customMessage = await _settingsRepo.getCustomLockMessage();
    final unlockDuration = await _settingsRepo.getDefaultUnlockDurationSeconds();
    final passwordHash = await _settingsRepo.getSetting('password_hash');

    if (mounted) {
      setState(() {
        _waitingDurationSeconds = waitingDuration;
        _customMessageController.text = customMessage;
        _defaultUnlockDurationSeconds = unlockDuration;
        _hasExistingPassword = passwordHash != null && passwordHash.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
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

    await _settingsRepo.setSetting(
      'waiting_duration_seconds',
      _waitingDurationSeconds.toString(),
    );
    await _settingsRepo.setSetting(
      'custom_lock_message',
      _customMessageController.text.trim().isEmpty
          ? 'Tetap fokus pada tujuanmu.'
          : _customMessageController.text.trim(),
    );
    await _settingsRepo.setSetting(
      'default_unlock_duration_seconds',
      _defaultUnlockDurationSeconds.toString(),
    );

    if (password.isNotEmpty) {
      await _settingsRepo.setPassword(password);
      _passwordController.clear();
      _confirmPasswordController.clear();
      _hasExistingPassword = true;
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan berhasil disimpan.'),
          backgroundColor: AppColors.darkGreen,
        ),
      );
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
                const Text(
                  'Waktu tunggu sebelum opsi memasukkan password tersedia di layar kunci.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.darkGreenMuted,
                  ),
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
                const Text(
                  'Pesan motivasi yang ditampilkan saat layar terkunci.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.darkGreenMuted,
                  ),
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
                const Text(
                  'Durasi bawaan saat membuka akses aplikasi sementara.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.darkGreenMuted,
                  ),
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
                          style: TextStyle(
                            fontSize: 13,
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.darkGreenMuted,
                  ),
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
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.darkGreen,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                      _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
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
            onPressed: _saveSettings,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.darkGreen,
      ),
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
