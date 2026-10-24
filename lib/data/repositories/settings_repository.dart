abstract class SettingsRepository {
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);
  Future<int> getWaitingDurationSeconds();
  Future<String> getCustomLockMessage();
  Future<bool> verifyPassword(String plainPassword);
  Future<void> setPassword(String plainPassword);
  Future<int> getDefaultUnlockDurationSeconds();
}
