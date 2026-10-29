// Runs example/example.dart and checks everything it prints.
//
// The example uses only the core library, so this file has no @TestOn and
// runs on every platform the suite targets (VM, Node, and WebAssembly).
import 'dart:async';

import 'package:test/test.dart';

import '../example/example.dart' as example;

void main() {
  test('example/example.dart prints the tour', () {
    final printed = <String>[];
    runZoned(
      example.main,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    expect(printed.join('\n'), '''
DirectoryTree(roots: 1, nodes: 9, files: 5, issues: 0)
repo/
├── lib/
│   ├── src/
│   │   ├── tree.dart
│   │   └── tree.g.dart
│   └── main.dart
├── test/
│   └── tree_test.dart
└── README.md
search: repo, lib, src, tree.dart*, main.dart*, test, tree_test.dart*
collapsed lib: repo, lib, test, tree_test.dart, README.md
last row reused: true
range: /repo/lib/main.dart, /repo/test, /repo/test/tree_test.dart
lib: checked
repo: partial
removed: [5, 4, 3, 2]
inserted: []
changed: [1]''');
  });
}
