import '../models/block_session.dart';

abstract class BlockSessionRepository {
  Future<BlockSession?> getActiveSession();
  Future<int> createSession(BlockSession session);
  Future<void> updateSessionStatus(int sessionId, String status);
  Future<List<BlockSession>> getScheduledSessions();
}
