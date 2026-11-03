import '../models/focus_task.dart';

abstract class TaskRepository {
  Future<List<FocusTask>> getAllTasks();
  Future<List<FocusTask>> getPendingTasks();
  Future<int> addTask(String title);
  Future<void> toggleTaskCompletion(int id, bool isCompleted);
  Future<void> deleteTask(int id);
  Future<void> updateTask(int id, String newTitle);
}
