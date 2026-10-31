import '../../data/models/app_setting.dart';
import '../../data/repositories/settings_repository.dart';

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.waitingDurationSeconds,
    required this.customLockMessage,
    required this.defaultUnlockDurationSeconds,
    required this.hasExistingPassword,
  });

  final int waitingDurationSeconds;
  final String customLockMessage;
  final int defaultUnlockDurationSeconds;
  final bool hasExistingPassword;
}

/// Loads a complete settings snapshot and owns persistence/default normalization.
class SettingsService {
  SettingsService({required this.repository});

  final SettingsRepository repository;

  Future<SettingsSnapshot> load() async {
    final waitingDuration = await repository.getWaitingDurationSeconds();
    final message = await repository.getCustomLockMessage();
    final unlockDuration = await repository.getDefaultUnlockDurationSeconds();
    final passwordHash = await repository.getSetting(
      AppSetting.keyPasswordHash,
    );
    return SettingsSnapshot(
      waitingDurationSeconds: waitingDuration,
      customLockMessage: message,
      defaultUnlockDurationSeconds: unlockDuration,
      hasExistingPassword: passwordHash != null && passwordHash.isNotEmpty,
    );
  }

  Future<void> save({
    required int waitingDurationSeconds,
    required String customLockMessage,
    required int defaultUnlockDurationSeconds,
    required String password,
  }) async {
    final message = customLockMessage.trim();
    await repository.setSetting(
      AppSetting.keyWaitingDurationSeconds,
      waitingDurationSeconds.toString(),
    );
    await repository.setSetting(
      AppSetting.keyCustomLockMessage,
      message.isEmpty ? AppSetting.defaultCustomLockMessage : message,
    );
    await repository.setSetting(
      AppSetting.keyDefaultUnlockDurationSeconds,
      defaultUnlockDurationSeconds.toString(),
    );
    if (password.isNotEmpty) await repository.setPassword(password);
  }
}
