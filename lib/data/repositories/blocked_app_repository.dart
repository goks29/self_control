import '../models/blocked_app.dart';

abstract class BlockedAppRepository {
  Future<List<BlockedApp>> getAllApps();
  Future<List<BlockedApp>> getSelectedApps();
  Future<BlockedApp?> getAppByPackageName(String packageName);
  Future<void> saveApps(List<BlockedApp> apps);
  Future<void> setAppSelected(String packageName, bool isSelected);
}
