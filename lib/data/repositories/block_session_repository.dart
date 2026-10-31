import '../models/block_session.dart';

abstract class BlockSessionRepository {
  Future<BlockSession?> getActiveSession();
  Future<BlockSession?> getActiveSessionForPackage(String packageName);
  Future<int> createSession(BlockSession session);
  Future<void> updateSessionStatus(int sessionId, String status);
  Future<void> completeActiveSessionsForPackage(String packageName);
  Future<List<BlockSession>> getScheduledSessions();
}
