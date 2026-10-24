import '../models/activity_log.dart';

abstract class ActivityLogRepository {
  Future<void> logEvent(ActivityLog log);
  Future<List<ActivityLog>> getLogs({int? limit, int? offset});
  Future<Map<String, int>> getAttemptCountsByPackage({String? outcome = ActivityLog.outcomeConfirmed});
  Future<Map<String, int>> getOutcomeCounts();
  Future<void> clearAllLogs();
}
