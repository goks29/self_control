import 'dart:io';

void backupCorruptFiles(String dbPath, int timestamp) {
  if (dbPath == ':memory:' || dbPath.startsWith(':memory:')) return;

  // Copy every durable file before removing any originals. A failed backup must
  // never allow a fresh database to overwrite the only copy of user data.
  final files = [
    File(dbPath),
    File('$dbPath-wal'),
    File('$dbPath-journal'),
  ].where((file) => file.existsSync()).toList();
  for (final file in files) {
    final backup = File('${file.path}.corrupt.$timestamp');
    if (backup.existsSync()) {
      throw FileSystemException(
        'Corruption backup already exists',
        backup.path,
      );
    }
    file.copySync(backup.path);
  }
  for (final file in files) {
    file.deleteSync();
  }
  final shm = File('$dbPath-shm');
  if (shm.existsSync()) shm.deleteSync();
}
