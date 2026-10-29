/// Compiles and runs every 2.0.0 Dart example in MIGRATION.md.
///
/// Each 2.0.0 code block of the guide appears below verbatim, inside a test
/// that runs it. Blocks whose first line is `// directory_tree 1.x` show the
/// old API and are skipped; they were checked against the published 1.0.0.
///
/// The first test fails when a 2.0.0 block has no copy here. Every
/// `print(...); // output` line is an assertion: the printed value must equal
/// the comment. A `print(...);` followed by `// ...` lines promises those
/// lines as one multi-line output. The second test fails when a block's
/// output goes unchecked. The last group checks the behavior changes the
/// guide describes.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

/// The first line of every 1.x block in the guide.
const String _v1Marker = '// directory_tree 1.x';

void main() {
  final guide = File('MIGRATION.md').readAsStringSync();
  final allBlocks = RegExp(
    r'```dart\n([\s\S]*?)```',
  ).allMatches(guide).map((match) => match.group(1)!).toList();
  final blocks = allBlocks
      .where((block) => !block.startsWith(_v1Marker))
      .toList();

  /// The 2.0.0 block that contains [line].
  String block(String line) => blocks.singleWhere((b) => b.contains(line));

  test('every 2.0.0 Dart block is compiled by this file', () {
    final source = _normalize(
      File('test/migration_test.dart').readAsStringSync(),
    );
    expect(blocks, isNotEmpty);
    expect(
      allBlocks.length,
      greaterThan(blocks.length),
      reason: 'The guide shows 1.x blocks marked with "$_v1Marker".',
    );
    for (final guideBlock in blocks) {
      expect(
        source.contains(_normalize(guideBlock)),
        isTrue,
        reason:
            'Copy this MIGRATION.md block into test/migration_test.dart, or '
            'start it with "$_v1Marker" if it shows the old API:\n'
            '$guideBlock',
      );
    }
  });

  test('every 2.0.0 output comment is compared with the output', () {
    final source = File('test/migration_test.dart').readAsStringSync();
    final compared = {
      for (final match in RegExp(
        r"_expectedPrints\(block\('([^']+)'\)\)",
      ).allMatches(source))
        block(match.group(1)!),
    };
    for (final guideBlock in blocks) {
      final lines = guideBlock.split('\n');
      var prints = 0;
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trimLeft().startsWith('print(')) continue;
        prints++;
        final documented =
            _printLine.hasMatch(lines[i]) ||
            (i + 1 < lines.length && lines[i + 1].trimLeft().startsWith('// '));
        expect(
          documented,
          isTrue,
          reason:
              'Write guide prints as `print(...); // output`, or follow '
              'them with `// ` output lines: ${lines[i]}',
        );
      }
      expect(
        prints == 0 || compared.contains(guideBlock),
        isTrue,
        reason:
            'Compare the output of this block with '
            '_expectedPrints(block(...)):\n$guideBlock',
      );
    }
  });

  group('before and after', () {
    test('build a tree from paths', () async {
      final printed = await _prints(_buildATree);
      expect(printed, _expectedPrints(block('final children = ')));
    });

    test('attach data to entries', () async {
      final printed = await _prints(_attachData);
      expect(printed, _expectedPrints(block('final sized = ')));
    });

    test('visible rows for a list view', () async {
      final printed = await _prints(() => _visibleRows(_sharedTree()));
      expect(printed, _expectedPrints(block('final top = ')));
    });

    test('expand and collapse', () async {
      final printed = await _prints(() => _expandAndCollapse(_sharedTree()));
      expect(printed, _expectedPrints(block('rows.toggleNode(lib)')));
    });

    test('filter and search', () async {
      final printed = await _prints(() => _filterAndSearch(_sharedTree()));
      expect(printed, _expectedPrints(block('final query = ')));
    });

    test('selection', () async {
      final printed = await _prints(() => _selection(_sharedTree()));
      expect(printed, _expectedPrints(block('var selection = ')));
    });

    test('diff visible rows for an animated list', () async {
      final printed = await _prints(() => _diffRows(_sharedTree()));
      expect(printed, _expectedPrints(block('ListDiff.compute(')));
    });

    test('print a tree', () async {
      final printed = await _prints(() => _printATree(_sharedTree()));
      expect(printed, _expectedPrints(block('print(tree.render());')));
    });

    test('source roots and empty directories', () async {
      final printed = await _prints(_sourceRoots);
      expect(printed, _expectedPrints(block('final rooted = ')));
    });

    test('options: case, roots, and order', () async {
      final printed = await _prints(_options);
      expect(printed, _expectedPrints(block('final options = ')));
    });

    test('a typed comparator', () async {
      final printed = await _prints(_typedComparator);
      expect(printed, _expectedPrints(block('final bySize = ')));
    });

    test('reveal and find a node', () async {
      final printed = await _prints(() => _revealAndFind(_sharedTree()));
      expect(printed, _expectedPrints(block('final found = ')));
    });
  });

  group('the behavior changes hold', () {
    test('paths are case sensitive by default', () {
      final paths = ['/Repo/a.txt', '/repo/b.txt'];
      expect(DirectoryTree.fromPaths(paths).roots, hasLength(2));
      final folded = DirectoryTree.fromPaths(
        paths,
        options: const TreeOptions(paths: PathPolicy.caseInsensitive),
      );
      expect(folded.roots, [const NodeId('/repo')]);
    });

    test('node ids are canonical paths and there is no synthetic root', () {
      final tree = _sharedTree();
      expect(tree.nodes.map((node) => node.id.value), [
        '/repo',
        '/repo/lib',
        '/repo/lib/src',
        '/repo/lib/src/tree.dart',
        '/repo/lib/main.dart',
        '/repo/README.md',
      ]);
      expect(tree.rootNodes.single.parent, isNull);
    });

    test('top-level nodes are not hoisted', () {
      final tree = DirectoryTree.fromPaths(['/x/', '/x/y/z.txt']);
      expect(tree.rootNodes.single.name, 'x');
      final rows = tree.flatten(compactFolders: true);
      expect(rows.map((row) => row.label), ['x/y', 'z.txt']);
    });

    test('duplicate entries: the later one wins at the first position', () {
      final tree = DirectoryTree<String>.build([
        TreeEntry.file('/d/a.txt', data: 'first'),
        TreeEntry.file('/d/b.txt'),
        TreeEntry.file('/d/a.txt', data: 'second'),
      ]);
      expect(tree.nodeAt('/d/a.txt')!.data, 'second');
      expect(tree.entries.map((entry) => entry.data), ['second', null]);
    });

    test('path parsing keeps whitespace, rejects escaping .., keeps UNC', () {
      final tree = DirectoryTree.fromPaths([
        ' /p/q.txt',
        '../up/a.txt',
        r'\\server\share\a.txt',
        '',
        r'C:\work\..\repo\a.txt',
      ]);
      expect(tree.nodeAt(' /p/q.txt'), isNotNull);
      expect(tree.nodeAt('/p/q.txt'), isNull);
      expect(tree.nodeAt('//server/share/a.txt'), isNotNull);
      expect(tree.nodeAt('C:/repo/a.txt'), isNotNull);
      expect(tree.issues.map((issue) => (issue.kind, issue.path)), [
        (TreeIssueKind.invalidPath, '../up/a.txt'),
        (TreeIssueKind.invalidPath, ''),
      ]);
      final conflict = DirectoryTree.fromPaths(['/r/a', '/r/a/b.txt']);
      expect(conflict.issues.single.kind, TreeIssueKind.conflict);
    });

    test('names come from paths', () {
      final tree = DirectoryTree.build([
        const TreeEntry.file('/r/a.txt', data: 'shown as anything else'),
      ]);
      expect(tree.nodeAt('/r/a.txt')!.name, 'a.txt');
    });

    test('TreePath.parse rejects inputs that 1.x basename accepted', () {
      expect(() => TreePath.parse(''), throwsFormatException);
      expect(() => TreePath.parse('..'), throwsFormatException);
      expect(TreePath.tryParse(''), isNull);
      expect(TreePath.tryParse('..'), isNull);
      expect(TreePath.parse('a/..').name, '.');
    });

    test('siblings sort directories first, in natural order', () {
      final tree = DirectoryTree.fromPaths([
        '/s/file10.txt',
        '/s/file2.txt',
        '/s/B.txt',
        '/s/a.txt',
        '/s/z/q.txt',
      ]);
      expect(tree.childrenOf(tree.roots.single).map((node) => node.name), [
        'z',
        'a.txt',
        'B.txt',
        'file2.txt',
        'file10.txt',
      ]);
    });

    test('colliding top-level labels read like paths', () {
      final tree = DirectoryTree.fromPaths(['/q/a/src/x.txt', '/q/b/src/y']);
      expect(tree.rootNodes.map((node) => node.label), ['a/src', 'b/src']);
    });

    test('filters reveal matches in a state that can be collapsed', () {
      final tree = _sharedTree();
      var rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: TreeQuery.parse('tree'),
      );
      expect(rows.map((row) => row.label), ['repo', 'lib', 'src', 'tree.dart']);
      rows = rows.collapseNode(tree.idOf('/repo/lib')!);
      expect(rows.map((row) => row.label), ['repo', 'lib']);
      final hidden = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: TreeQuery.parse('tree'),
        expandMatches: false,
      );
      expect(hidden.map((row) => row.label), ['repo']);
    });

    test('query syntax: ext skips directories, globs, literal quotes', () {
      final tree = DirectoryTree.fromPaths([
        '/r/x.d/',
        '/r/a*b.txt',
        '/r/axb.txt',
      ]);
      List<String> names(String query) => [
        for (final node in tree.nodes)
          if (TreeQuery.parse(query).matches(node)) node.name,
      ];
      expect(names('ext:d'), isEmpty);
      expect(names('a*b'), isEmpty); // a glob over the whole name
      expect(names('a*b.txt'), ['a*b.txt', 'axb.txt']);
      expect(names('"a*b"'), ['a*b.txt']);
    });

    test('hasChildren is false when the filter hides every child', () {
      final tree = DirectoryTree.fromPaths(['/r/match/x.txt']);
      final rows = tree.flatten(filter: TreeQuery.parse('match'));
      final row = rows.rowOf(tree.idOf('/r/match')!)!;
      expect(row.hasChildren, isFalse);
      expect(tree.flatten().rowOf(row.id)!.hasChildren, isTrue);
    });

    test('flatten and render expand everything by default', () {
      final tree = _sharedTree();
      expect(tree.flatten(), hasLength(tree.length));
      expect(tree.render().split('\n'), hasLength(tree.length));
    });

    test('state operations return new values', () {
      final id = const NodeId('/repo/lib');
      const expansion = ExpansionState.collapsed();
      final expanded = expansion.toggle(id);
      expect(expansion.isExpanded(id), isFalse);
      expect(expanded.isExpanded(id), isTrue);
      expect(identical(expanded.expand(id), expanded), isTrue);
      expect(_sharedTree().nodes, isA<List<TreeNode<Object?>>>());
      expect(
        () => _sharedTree().nodes.removeLast(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('single selection mode toggles off', () {
      final id = const NodeId('/r/a.txt');
      final selection = const SelectionState.empty().toggle(id).toggle(id);
      expect(selection.selected, isEmpty);
    });

    test('empty directories are leaves for check states', () {
      final tree = DirectoryTree.fromPaths(['/r/a.txt', '/r/empty/']);
      final root = tree.roots.single;
      final empty = tree.idOf('/r/empty')!;
      var selection = const SelectionState.empty(mode: SelectionMode.multiple);
      selection = selection.check(tree, tree.idOf('/r/a.txt')!);
      expect(selection.checkStateOf(tree, root), CheckState.partial);
      selection = selection.check(tree, empty);
      expect(selection.checkStateOf(tree, empty), CheckState.checked);
      expect(selection.checkStateOf(tree, root), CheckState.checked);
    });

    test('row diffs reject duplicate keys', () {
      expect(
        () => ListDiff.compute(['a'], ['a', 'a'], keyOf: (item) => item),
        throwsArgumentError,
      );
    });
  });
}

/// The tree that the guide's examples share, from its first 2.0.0 block.
DirectoryTree<Object?> _sharedTree() => DirectoryTree.fromPaths([
  '/repo/lib/main.dart',
  '/repo/lib/src/tree.dart',
  '/repo/README.md',
]);

// The 2.0.0 blocks of MIGRATION.md, verbatim, in guide order. Blocks that
// use the shared tree take it as `tree`.

void _buildATree() {
  final tree = DirectoryTree.fromPaths([
    '/repo/lib/main.dart',
    '/repo/lib/src/tree.dart',
    '/repo/README.md',
  ]);
  final repo = tree.rootNodes.single;
  final children = tree.childrenOf(repo.id);
  print(repo.name); // repo
  print(children.map((node) => node.name)); // (lib, README.md)
  print(tree.nodeAt('/repo/lib/main.dart')!.id); // /repo/lib/main.dart
}

void _attachData() {
  final sized = DirectoryTree<int>.build([
    TreeEntry.file('/repo/lib/main.dart', data: 1024),
    TreeEntry.directory('/repo/assets'),
  ]);
  print(sized.nodeAt('/repo/lib/main.dart')!.data); // 1024
  print(sized.nodeAt('/repo/assets')!.isExplicit); // true
}

void _visibleRows(DirectoryTree<Object?> tree) {
  final top = tree.flatten(expansion: const ExpansionState.collapsed());
  print(top.map((row) => row.label)); // (repo)
  final rows = tree.flatten(); // every directory is expanded by default
  final labels = rows.map((row) => row.label);
  print(labels); // (repo, lib, src, tree.dart, main.dart, README.md)
  print(rows.map((row) => row.depth)); // (0, 1, 2, 3, 2, 1)
}

void _expandAndCollapse(DirectoryTree<Object?> tree) {
  final lib = tree.idOf('/repo/lib')!;
  var rows = tree.flatten(expansion: ExpansionState.withExpanded(tree.roots));
  rows = rows.toggleNode(lib); // new rows; only the changed rows are built
  print(rows.map((row) => row.label)); // (repo, lib, src, main.dart, README.md)
  rows = rows.collapseNode(lib);
  print(rows.map((row) => row.label)); // (repo, lib, README.md)

  // Without rows, change the state itself. It is immutable: keep the result.
  var expansion = const ExpansionState.collapsed();
  expansion = expansion.expand(tree.roots.single).expand(lib);
  print(expansion.isExpanded(lib)); // true
}

void _filterAndSearch(DirectoryTree<Object?> tree) {
  final query = TreeQuery.parse('ext:dart !main');
  final matches = tree.flatten(
    expansion: const ExpansionState.collapsed(),
    filter: query,
  );
  print(matches.map((row) => row.label)); // (repo, lib, src, tree.dart)
  print(matches.map((row) => row.isMatch)); // (false, false, false, true)

  // Combine a query with your own predicate.
  final dotFiles = TreeFilter.where<Object?>((n) => n.name.startsWith('.'));
  print(tree.flatten(filter: query.and(dotFiles.negate())).length); // 4
}

void _selection(DirectoryTree<Object?> tree) {
  final rows = tree.flatten();
  final order = rows.map((row) => row.id);
  final repo = tree.roots.single;
  var selection = const SelectionState.empty(mode: SelectionMode.multiple);
  selection = selection.toggle(rows[1].id); // lib; also sets the anchor
  selection = selection.extendTo(rows[3].id, order); // to tree.dart
  print(selection.length); // 3
  print(selection.checkStateOf(tree, repo)); // CheckState.partial

  // Checkboxes: check a folder to select every leaf below it.
  final lib = tree.idOf('/repo/lib')!;
  selection = selection.check(tree, lib);
  print(selection.checkStateOf(tree, lib)); // CheckState.checked
}

void _diffRows(DirectoryTree<Object?> tree) {
  final opened = ExpansionState.withExpanded(tree.roots);
  final before = tree.flatten(expansion: opened);
  final after = tree.flatten();
  final diff = ListDiff.compute(before, after, keyOf: (row) => row.id);
  print(diff.removedIndices); // []
  print(diff.insertedIndices); // [2, 3, 4]
  print(diff.changedIndices); // [1]
}

void _printATree(DirectoryTree<Object?> tree) {
  print(tree.render());
  // repo/
  // ├── lib/
  // │   ├── src/
  // │   │   └── tree.dart
  // │   └── main.dart
  // └── README.md
}

void _sourceRoots() {
  final rooted = DirectoryTree.fromPaths([
    '/repo/', // a directory entry, like a 1.x source root
    '/repo/lib/main.dart',
    '/repo/assets/', // kept although empty, like a 1.x selected directory
  ]);
  print(rooted.render(style: TreeStyle.indent));
  // repo/
  //   assets/
  //   lib/
  //     main.dart
}

void _options() {
  final options = DirectoryTree.fromPaths(
    [r'C:\Repo\b\x.dart', r'c:\Repo\a.md'],
    options: const TreeOptions(
      paths: PathPolicy.caseInsensitive,
      roots: TreeRoots.fixed([r'C:\Repo']),
      order: TreeOrder.alphabetical, // files and directories mixed
    ),
  );
  print(options.rootNodes.single.path); // C:/Repo
  print(options.roots.single); // c:/repo
  print(options.nodes.map((node) => node.name)); // (Repo, a.md, b, x.dart)
}

void _typedComparator() {
  final bySize = TreeOrder.by<int>(
    (a, b) => (a.data ?? 0).compareTo(b.data ?? 0),
  );
  final sizes = DirectoryTree<int>.build([
    TreeEntry.file('/r/big.bin', data: 900),
    TreeEntry.file('/r/small.txt', data: 5),
  ], options: TreeOptions(order: bySize));
  print(sizes.files.map((node) => node.name)); // (small.txt, big.bin)
}

void _revealAndFind(DirectoryTree<Object?> tree) {
  final found = tree.idOf('/repo/lib/src/tree.dart')!;
  print(tree.ancestorsOf(found).map((node) => node.name)); // (src, lib, repo)
  final rows = tree.flatten(expansion: const ExpansionState.collapsed());
  print(rows.reveal(found).indexOfNode(found)); // 3
}

/// Trims every line, collapses inner whitespace, and drops blank lines, so
/// indentation inside a test does not hide a copied block.
String _normalize(String code) => code
    .split('\n')
    .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((line) => line.isNotEmpty)
    .join('\n');

/// A `print(...); // output` line; group 1 is the promised output.
final RegExp _printLine = RegExp(r'^\s*print\(.*\);\s*// (.*)$');

/// The outputs that the print lines in [block] promise.
///
/// A `print(...); // output` line promises `output`. A print line without a
/// trailing comment promises the `// ` lines right after it, joined with
/// line breaks, for values that print on several lines.
List<String> _expectedPrints(String block) {
  final lines = block.split('\n');
  final expected = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].trimLeft().startsWith('print(')) continue;
    final single = _printLine.firstMatch(lines[i]);
    if (single != null) {
      expected.add(single.group(1)!);
      continue;
    }
    final output = <String>[];
    while (i + 1 < lines.length && lines[i + 1].trimLeft().startsWith('// ')) {
      i++;
      output.add(lines[i].trimLeft().substring(3));
    }
    expected.add(output.join('\n'));
  }
  return expected;
}

/// Runs [body] and returns everything it printed.
Future<List<String>> _prints(FutureOr<void> Function() body) async {
  final printed = <String>[];
  await runZoned(
    () async => body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}
