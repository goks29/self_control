import '../models/block_rule.dart';

abstract class BlockRuleRepository {
  Future<List<BlockRule>> getAllRules();
  Future<BlockRule?> getActiveRule();
  Future<void> saveRule(BlockRule rule);
  Future<void> updateRule(BlockRule rule);
  Future<void> deleteRule(int id);
}
