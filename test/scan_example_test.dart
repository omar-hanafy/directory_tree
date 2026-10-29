// Runs example/scan_directory.dart against temporary directories.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../example/scan_directory.dart' as example;

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scan_example_');
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  /// Creates directories (paths ending in '/') and files under [temp].
  void create(List<String> paths) {
    for (final path in paths) {
      final full = '${temp.path}/$path';
      if (path.endsWith('/')) {
        Directory(full).createSync(recursive: true);
      } else {
        File(full).createSync(recursive: true);
      }
    }
  }

  /// Runs the example with [args] and returns everything it printed.
  Future<List<String>> run(List<String> args) async {
    final printed = <String>[];
    await runZoned(
      () => example.main(args),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    return printed;
  }

  test('prints the tree to the printed depth and the counts', () async {
    create([
      'lib/src/deep/tree.dart',
      'lib/main.dart',
      'assets/',
      'README.md',
      '.git/HEAD',
      '.env',
    ]);
    final name = temp.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

    final printed = await run([temp.path]);

    expect(example.printedDepth, 2);
    expect(printed.join('\n'), '''
$name/
├── assets/
├── lib/
│   ├── src/
│   └── main.dart
└── README.md

5 directories, 3 files''');
  });

  test('defaults to the current directory', () async {
    // Scanning `.` without arguments must equal scanning it explicitly.
    expect(await run(const []), await run(const ['.']));
  });

  test('reports a directory it cannot list and keeps going', () async {
    if (Platform.isWindows) {
      markTestSkipped('chmod is not available on Windows');
      return;
    }
    final id = Process.runSync('id', ['-u']);
    if (id.exitCode != 0 || (id.stdout as String).trim() == '0') {
      markTestSkipped('root can list any directory');
      return;
    }
    create(['locked/secret.txt', 'open.txt']);
    final locked = '${temp.path}/locked';
    Process.runSync('chmod', ['000', locked]);
    addTearDown(() => Process.runSync('chmod', ['755', locked]));

    final printed = await run([temp.path]);

    expect(printed, contains('2 directories, 1 files'), reason: '$printed');
    expect(
      printed.where((line) => line.startsWith('skipped $locked')),
      hasLength(1),
      reason: '$printed',
    );
  });

  test('fails with exit code 1 for a missing directory', () async {
    final missing = '${temp.path}/missing';
    final result = Process.runSync(Platform.resolvedExecutable, [
      'run',
      'example/scan_directory.dart',
      missing,
    ]);
    expect(result.exitCode, 1, reason: '${result.stderr}');
    expect(result.stdout, isEmpty);
    expect(result.stderr, startsWith('Cannot scan $missing: '));
  });
}
