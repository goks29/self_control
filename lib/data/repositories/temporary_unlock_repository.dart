import '../models/temporary_unlock.dart';

abstract class TemporaryUnlockRepository {
  Future<TemporaryUnlock?> getActiveUnlockForApp(int appId);
  Future<TemporaryUnlock?> getActiveUnlockForPackage(String packageName);
  Future<int> createUnlock(TemporaryUnlock unlock);
  Future<void> updateUnlockStatus(int unlockId, String status);
  Future<List<String>> expireOutdatedUnlocks();
}
