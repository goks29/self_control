import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:self_control/core/platform/database_files.dart';

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('backup_safety_');
    path = p.join(dir.path, 'data.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('backs up main, WAL, and journal before removing originals', () {
    for (final suffix in ['', '-wal', '-journal', '-shm']) {
      File('$path$suffix').writeAsStringSync('original$suffix');
    }
    backupCorruptFiles(path, 123);
    for (final suffix in ['', '-wal', '-journal']) {
      expect(
        File('$path$suffix.corrupt.123').readAsStringSync(),
        'original$suffix',
      );
      expect(File('$path$suffix').existsSync(), isFalse);
    }
    expect(File('$path-shm').existsSync(), isFalse);
  });

  test('failed sidecar backup leaves all original files intact', () {
    File(path).writeAsStringSync('main');
    File('$path-wal').writeAsStringSync('wal');
    Directory('$path-wal.corrupt.123').createSync();
    expect(
      () => backupCorruptFiles(path, 123),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(path).readAsStringSync(), 'main');
    expect(File('$path-wal').readAsStringSync(), 'wal');
    expect(File('$path.corrupt.123').readAsStringSync(), 'main');
  });

  test('existing backup is never overwritten', () {
    File(path).writeAsStringSync('new');
    File('$path.corrupt.123').writeAsStringSync('previous');
    expect(
      () => backupCorruptFiles(path, 123),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(path).readAsStringSync(), 'new');
    expect(File('$path.corrupt.123').readAsStringSync(), 'previous');
  });

  test('in-memory database needs no file operations', () {
    expect(() => backupCorruptFiles(':memory:', 123), returnsNormally);
  });
}
