/// Compiles and runs every Dart example in README.md.
///
/// Each README Dart block appears below verbatim, inside a test that runs
/// it. The first test fails when a README block has no copy here. Output is
/// checked in one of two ways:
///
/// * every `print(...); // output` line is an assertion: the printed value
///   must equal the comment;
/// * a block whose output spans several lines (such as `render()`) is
///   followed in the README by a ```text block, and the test compares
///   everything the block printed with that text.
///
/// The second test fails when a block's prints go unchecked, and the third
/// when a ```text block does not directly follow a checked Dart block. Edit
/// an example in both places, and the suite proves the README still
/// compiles and tells the truth.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/io.dart';
import 'package:test/test.dart';

void main() {
  final readme = File('README.md').readAsStringSync();
  final blocks = _readmeBlocks(readme);

  /// The README Dart block that contains [line].
  _Block block(String line) =>
      blocks.dartBlocks.singleWhere((b) => b.code.contains(line));

  test('every README Dart block is compiled by this file', () {
    final source = _normalize(File('test/readme_test.dart').readAsStringSync());
    expect(blocks.dartBlocks, isNotEmpty);
    final missing = [
      for (final readmeBlock in blocks.dartBlocks)
        if (!source.contains(_normalize(readmeBlock.code))) readmeBlock.code,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'Copy these README blocks into test/readme_test.dart:\n'
          '${missing.join('\n---\n')}',
    );
  });

  test('every README print is compared with the output', () {
    final source = File('test/readme_test.dart').readAsStringSync();
    final comments = _checkedBlocks(source, '_expectedPrints', block);
    final outputs = _checkedBlocks(source, '_expectedOutput', block);
    for (final readmeBlock in blocks.dartBlocks) {
      final prints = readmeBlock.code
          .split('\n')
          .where((line) => line.trimLeft().startsWith('print('))
          .toList();
      if (prints.isEmpty) continue;
      if (readmeBlock.output != null) {
        expect(
          outputs.contains(readmeBlock),
          isTrue,
          reason:
              'Compare the output of this block with '
              '_expectedOutput(block(...)):\n${readmeBlock.code}',
        );
        continue;
      }
      for (final line in prints) {
        expect(
          _printLine.hasMatch(line),
          isTrue,
          reason:
              'Write README prints as `print(...); // output`, or put the '
              'output in a ```text block right after the Dart block: $line',
        );
      }
      expect(
        comments.contains(readmeBlock),
        isTrue,
        reason:
            'Compare the output of this block with '
            '_expectedPrints(block(...)):\n${readmeBlock.code}',
      );
    }
  });

  test('every README text block is the checked output of a Dart block', () {
    final source = File('test/readme_test.dart').readAsStringSync();
    final outputs = _checkedBlocks(source, '_expectedOutput', block);
    expect(
      blocks.orphanTextBlocks,
      isEmpty,
      reason:
          'A ```text block must directly follow the Dart block whose '
          'output it shows.',
    );
    for (final readmeBlock in blocks.dartBlocks) {
      if (readmeBlock.output == null) continue;
      expect(
        outputs.contains(readmeBlock),
        isTrue,
        reason:
            'Compare this output with _expectedOutput(block(...)):\n'
            '${readmeBlock.output}',
      );
    }
  });

  test('quick start', () async {
    final printed = await _prints(() {
      final tree = DirectoryTree.fromPaths([
        '/repo/lib/src/tree.dart',
        '/repo/lib/main.dart',
        '/repo/test/tree_test.dart',
        '/repo/README.md',
      ]);
      print(tree.render());
    });
    expect(printed.join('\n'), _expectedOutput(block('print(tree.render());')));
  });

  test('rows for a list view', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      var rows = tree.flatten(expansion: const ExpansionState.collapsed());
      rows = rows.toggleNode(rows.first.id); // the user opened "repo"

      for (final row in rows) {
        final arrow = row.hasChildren ? (row.isExpanded ? 'v ' : '> ') : '  ';
        print('${'  ' * row.depth}$arrow${row.label}');
      }
    });
    expect(printed.join('\n'), _expectedOutput(block('final arrow = ')));
  });

  test('paths', () async {
    final printed = await _prints(() {
      print(TreePath.parse(r'C:\work\..\repo\')); // C:/repo
      print(TreePath.parse(r'\\server\share\a.txt').root); // //server/share/
      print(TreePath.parse('a//./b/')); // a/b
      print(TreePath.tryParse('../outside')); // null
    });
    expect(printed, _expectedPrints(block('TreePath.tryParse(')));
  });

  test('case sensitivity', () async {
    final printed = await _prints(() {
      const paths = ['/Repo/README.md', '/repo/readme.md'];
      print(DirectoryTree.fromPaths(paths).fileCount); // 2

      final folded = DirectoryTree.fromPaths(
        paths,
        options: const TreeOptions(paths: PathPolicy.caseInsensitive),
      );
      print(folded.fileCount); // 1
      print(folded.files.single.path); // /repo/readme.md
    });
    expect(printed, _expectedPrints(block('final folded = ')));
  });

  test('entries with typed data', () async {
    final printed = await _prints(() {
      final sized = DirectoryTree<int>.build([
        TreeEntry.file('/repo/lib/main.dart', data: 1024),
        TreeEntry.file('/repo/README.md', data: 300),
        TreeEntry.directory('/repo/assets'),
      ]);
      print(sized.nodeAt('/repo/lib/main.dart')!.data); // 1024
      print(sized.nodeAt('/repo/assets')!.isExplicit); // true
      print(sized.nodeAt('/repo/lib')!.isExplicit); // false
    });
    expect(printed, _expectedPrints(block('final sized = ')));
  });

  test('ids and lookups', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final lib = tree.idOf('/repo/lib')!;
      print(lib.value); // /repo/lib
      print(tree.childrenOf(lib).map((node) => node.name)); // (src, main.dart)

      final file = tree.nodeAt('/repo/lib/src/tree.dart')!;
      print(tree.parentOf(file.id)!.name); // src
      print(tree.ancestorsOf(file.id).map((n) => n.name)); // (src, lib, repo)
      print(tree.isAncestor(lib, file.id)); // true
    });
    expect(printed, _expectedPrints(block('print(lib.value);')));
  });

  test('roots', () async {
    final printed = await _prints(() {
      const sources = ['/home/me/a/src/x.dart', '/home/me/b/src/y.dart'];
      for (final roots in const [
        TreeRoots.minimal(),
        TreeRoots.commonAncestor(),
        TreeRoots.fixed(['/home/me']),
        TreeRoots.filesystem(),
      ]) {
        final rooted = DirectoryTree.fromPaths(
          sources,
          options: TreeOptions(roots: roots),
        );
        final labels = rooted.rootNodes.map((node) => node.label).join(', ');
        print('$roots: $labels');
      }
    });
    expect(printed.join('\n'), _expectedOutput(block('const sources = ')));
  });

  test('ordering', () async {
    final printed = await _prints(() {
      final names = DirectoryTree.fromPaths([
        '/d/file10.txt',
        '/d/file2.txt',
        '/d/Beta/',
        '/d/alpha.txt',
      ]);
      print(names.render());
    });
    expect(printed.join('\n'), _expectedOutput(block('final names = ')));
  });

  test('ordering by data', () async {
    final printed = await _prints(() {
      final bySizeDescending = TreeOrder.by<int>(
        (a, b) => (b.data ?? 0).compareTo(a.data ?? 0),
      );
      const files = [
        TreeEntry.file('/repo/small.txt', data: 10),
        TreeEntry.file('/repo/big.bin', data: 4096),
        TreeEntry.file('/repo/mid.md', data: 300),
      ];
      final bySize = DirectoryTree<int>.build(
        files,
        options: TreeOptions(order: bySizeDescending),
      );
      print(bySize.files.map((n) => n.name)); // (big.bin, mid.md, small.txt)
    });
    expect(printed, _expectedPrints(block('final bySizeDescending = ')));
  });

  test('issues', () async {
    final printed = await _prints(() {
      final checked = DirectoryTree.fromPaths([
        '',
        '../up.txt',
        '/r/a.txt',
        '/r/a.txt/b.txt',
      ]);
      for (final issue in checked.issues) {
        print(issue);
      }
    });
    expect(printed.join('\n'), _expectedOutput(block('final checked = ')));
  });

  test('updating a tree', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final next = tree.rebuild(
        (builder) => builder
          ..addFile('/repo/lib/src/rows.dart')
          ..remove('/repo/test'),
      );
      print(next.render());
    });
    expect(printed.join('\n'), _expectedOutput(block('print(next.render());')));
  });

  test('incremental updates', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final expanded = tree.flatten();
      final collapsed = expanded.collapseNode(tree.idOf('/repo/lib')!);
      print(expanded.length); // 8
      print(collapsed.length); // 5
      print(identical(collapsed.last, expanded.last)); // true
    });
    expect(printed, _expectedPrints(block('final expanded = ')));
  });

  test('compact folders and hidden roots', () async {
    final printed = await _prints(() {
      const workspacePaths = ['/work/app/lib/src/main.dart', '/work/README.md'];
      final workspace = DirectoryTree.fromPaths(
        workspacePaths,
        options: const TreeOptions(roots: TreeRoots.fixed(['/work'])),
      );
      print(workspace.render(compactFolders: true, showRoots: false));
    });
    expect(printed.join('\n'), _expectedOutput(block('final workspace = ')));
  });

  test('keyboard navigation', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final rows = tree.flatten();
      final src = rows.indexOfNode(tree.idOf('/repo/lib/src')!);
      print(rows[src].label); // src
      print(rows[rows.parentIndexOf(src)!].label); // lib
      print(rows[rows.firstChildIndexOf(src)!].label); // tree.dart
      print(rows.firstChildIndexOf(rows.length - 1)); // null
    });
    expect(printed, _expectedPrints(block('final src = ')));
  });

  test('revealing a node', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      var rows = tree.flatten(expansion: const ExpansionState.collapsed());
      final target = tree.idOf('/repo/lib/src/tree.dart')!;
      rows = rows.reveal(target);
      print(rows.map((row) => row.label));
      print(rows.indexOfNode(target));
    });
    expect(
      printed.join('\n'),
      _expectedOutput(block('rows = rows.reveal(target);')),
    );
  });

  test('saving the expansion', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final search = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: TreeQuery.parse('tree'),
      );
      print(search.map((row) => row.label));
      print(search.expansion.toJson());

      final saved = search.requestedExpansion.toJson();
      print(saved);
      final restored = ExpansionState.fromJson(saved);
      print(tree.flatten(expansion: restored).map((row) => row.label));
    });
    expect(printed.join('\n'), _expectedOutput(block('final saved = ')));
  });

  test('search', () async {
    final printed = await _prints(() {
      final project = DirectoryTree.fromPaths([
        '/repo/lib/src/tree.dart',
        '/repo/lib/src/tree.g.dart',
        '/repo/lib/main.dart',
        '/repo/test/tree_test.dart',
        '/repo/docs/my notes.md',
        '/repo/dist/app.tar.gz',
        '/repo/README.md',
      ]);
      List<String> find(String text) {
        final query = TreeQuery.parse(text);
        return project.nodes.where(query.matches).map((n) => n.name).toList();
      }

      print(find('tree test')); // [tree_test.dart]
      print(find('tree !*.g.dart')); // [tree.dart, tree_test.dart]
      print(find('"my notes"')); // [my notes.md]
      print(find('ext:md')); // [my notes.md, README.md]
      print(find('ext:tar.gz')); // [app.tar.gz]
      print(find('type:dir path:lib')); // [lib, src]
      print(find('lib/')); // [src, main.dart]
      print(find('src/*.dart')); // [tree.dart, tree.g.dart]
    });
    expect(printed, _expectedPrints(block('List<String> find(')));
  });

  test('highlighting', () async {
    final printed = await _prints(() {
      String highlight(String text, TreeQuery query) {
        final buffer = StringBuffer();
        var last = 0;
        for (final range in query.matchRanges(text)) {
          buffer
            ..write(text.substring(last, range.start))
            ..write('[${text.substring(range.start, range.end)}]');
          last = range.end;
        }
        return (buffer..write(text.substring(last))).toString();
      }

      final query = TreeQuery.parse('tree test');
      print(highlight('tree_test.dart', query)); // [tree]_[test].dart
    });
    expect(printed, _expectedPrints(block('String highlight(')));
  });

  test('filters', () async {
    final project = _searchProject();
    final printed = await _prints(() {
      final dartFiles = TreeFilter.where<Object?>(
        (node) => node.isFile && node.path.extension == '.dart',
      );
      final generated = TreeFilter.where<Object?>(
        (node) => node.name.endsWith('.g.dart'),
      );
      final filter = dartFiles
          .and(generated.negate())
          .and(TreeQuery.parse('tree'));
      print(project.render(filter: filter));
    });
    expect(printed.join('\n'), _expectedOutput(block('final dartFiles = ')));
  });

  test('expandMatches: false', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final hidden = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: TreeQuery.parse('ext:md'),
        expandMatches: false,
      );
      print(hidden.map((row) => row.label)); // (repo)
    });
    expect(printed, _expectedPrints(block('final hidden = ')));
  });

  test('range selection', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final rows = tree.flatten();
      var selection = const SelectionState.empty(mode: SelectionMode.multiple);
      selection = selection.select(tree.idOf('/repo/lib/main.dart')!);
      selection = selection.extendTo(
        tree.idOf('/repo/test/tree_test.dart')!,
        rows.map((row) => row.id),
      );
      print(selection.selected.map((id) => id.value));
      print(selection.anchor!.value);
    });
    expect(printed.join('\n'), _expectedOutput(block('var selection = ')));
  });

  test('checkboxes', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      var checks = const SelectionState.empty(mode: SelectionMode.multiple);
      final lib = tree.idOf('/repo/lib')!;
      checks = checks.check(tree, lib);
      print(checks.checkStateOf(tree, lib)); // CheckState.checked
      print(checks.checkStateOf(tree, tree.roots.single)); // CheckState.partial
      print(checks.length); // 2
      print(checks.isSelected(lib)); // false

      const single = SelectionState.empty();
      print(single.canCheck(tree, lib)); // false
      print(single.canCheck(tree, tree.idOf('/repo/test')!)); // true

      print(SelectionState.fromJson(checks.toJson()) == checks); // true
    });
    expect(printed, _expectedPrints(block('var checks = ')));
  });

  test('ListDiff', () async {
    final tree = _quickStartTree();
    late List<TreeRow<Object?>> applied;
    late List<TreeRow<Object?>> target;
    final printed = await _prints(() {
      final before = tree.flatten();
      final after = before.collapseNode(tree.idOf('/repo/lib')!);
      final diff = ListDiff.compute(before, after, keyOf: (row) => row.id);
      print(diff.removedIndices); // [4, 3, 2]
      print(diff.insertedIndices); // []
      print(diff.changedIndices); // [1]

      final list = [...before];
      for (final index in diff.removedIndices) {
        list.removeAt(index);
      }
      for (final index in diff.insertedIndices) {
        list.insert(index, after[index]);
      }
      print(list.length); // 5
      applied = list;
      target = after;
    });
    expect(printed, _expectedPrints(block('final diff = ListDiff.compute(')));
    // `list` now has the keys of `after`, in the same order.
    expect(applied.map((row) => row.id), target.map((row) => row.id));
  });

  test('ListDiff moves', () async {
    final printed = await _prints(() {
      final moves = ListDiff.compute(
        ['a', 'b', 'c', 'd'],
        ['b', 'x', 'a', 'd'],
        keyOf: (item) => item,
      );
      print(moves); // ListDiff(removed: [2, 0], inserted: [1, 2], changed: [])
    });
    expect(printed, _expectedPrints(block('final moves = ')));
  });

  test('TreeDiff', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      final next = tree.rebuild(
        (builder) => builder
          ..addFile('/repo/lib/src/rows.dart')
          ..remove('/repo/test'),
      );
      print(TreeDiff.compute(tree, next));
    });
    expect(
      printed.join('\n'),
      _expectedOutput(block('print(TreeDiff.compute(tree, next));')),
    );
  });

  test('rendering with a style and maxDepth', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      print(tree.render(style: TreeStyle.ascii, maxDepth: 1));
    });
    expect(printed.join('\n'), _expectedOutput(block('TreeStyle.ascii')));
  });

  test('rendering with a label', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      print(
        tree.render(
          style: TreeStyle.indent,
          label: (row) => row.node.isDirectory ? '[${row.label}]' : row.label,
        ),
      );
    });
    expect(printed.join('\n'), _expectedOutput(block('TreeStyle.indent')));
  });

  test('scanning the file system', () async {
    final temp = Directory.systemTemp.createTempSync('readme_scan_');
    addTearDown(() => temp.deleteSync(recursive: true));
    for (final file in [
      'lib/main.dart',
      'lib/src/tree.dart',
      'README.md',
      'build/out.txt',
      '.git/HEAD',
    ]) {
      File('${temp.path}/$file').createSync(recursive: true);
    }
    final projectPath = temp.path;

    final printed = await _prints(() async {
      final scanner = DirectoryScanner(
        maxDepth: 2,
        skip: (entity) => entity.path.endsWith('build'),
        onError: (error) => print('skipped ${error.path}: ${error.message}'),
      );
      final scanned = await scanner.scanTree(projectPath);
      print(scanned.render(showRoots: false));
    });
    expect(printed.join('\n'), _expectedOutput(block('final scanner = ')));
  });

  test('gotcha: inferred directories', () async {
    final printed = await _prints(() {
      final docs = DirectoryTree.fromPaths(['/r/docs/a.md', '/r/b.txt']);
      final emptied = docs.rebuild((builder) => builder.remove('/r/docs/a.md'));
      print(emptied.nodeAt('/r/docs')); // null

      final kept = docs.rebuild(
        (builder) => builder
          ..addDirectory('/r/docs')
          ..remove('/r/docs/a.md'),
      );
      print(kept.nodeAt('/r/docs')); // DirectoryNode(/r/docs, children: 0)
    });
    expect(printed, _expectedPrints(block('final docs = ')));
  });

  test('gotcha: TreeDiff ignores sibling order', () async {
    final printed = await _prints(() {
      const paths = ['/r/b/', '/r/a.txt'];
      final byKind = DirectoryTree.fromPaths(paths);
      final byName = DirectoryTree.fromPaths(
        paths,
        options: const TreeOptions(order: TreeOrder.alphabetical),
      );
      print(TreeDiff.compute(byKind, byName).isEmpty); // true
    });
    expect(printed, _expectedPrints(block('final byKind = ')));
  });

  test('gotcha: unknown ids', () async {
    final tree = _quickStartTree();
    final printed = await _prints(() {
      const missing = NodeId('/repo/gone');
      print(tree[missing]); // null
      print(tree.indexOf(missing)); // -1
      print(tree.childrenOf(missing).isEmpty); // true
      final rows = tree.flatten();
      print(identical(rows.toggleNode(missing), rows)); // true
    });
    expect(printed, _expectedPrints(block('const missing = ')));
  });

  test('the README prose claims hold', () {
    final tree = _quickStartTree();
    final lib = tree.idOf('/repo/lib')!;
    final src = tree.idOf('/repo/lib/src')!;
    final file = tree.idOf('/repo/README.md')!;
    const missing = NodeId('/repo/gone');

    // Directories first, then natural, case-insensitive names.
    expect(tree.childrenOf(tree.roots.single).map((node) => node.name), [
      'lib',
      'test',
      'README.md',
    ]);
    // The same paths in any order give an equal tree and node order.
    final shuffled = DirectoryTree.fromPaths([
      '/repo/README.md',
      '/repo/test/tree_test.dart',
      '/repo/lib/main.dart',
      '/repo/lib/src/tree.dart',
    ]);
    expect(shuffled, tree);
    expect(shuffled.nodes.map((node) => node.id), tree.nodes.map((n) => n.id));

    // A subtree is the slice of nodes at indexOf, subtreeSizeOf long.
    final start = tree.indexOf(lib);
    expect(
      tree.nodes.sublist(start, start + tree.subtreeSizeOf(lib)).skip(1),
      tree.descendantsOf(lib),
    );

    // Lookups of unknown ids.
    expect(tree.subtreeSizeOf(missing), 0);
    expect(tree.contains(missing), isFalse);
    expect(tree.isAncestor(missing, lib), isFalse);
    expect(tree.nodeAt('/repo/gone'), isNull);
    final rows = tree.flatten();
    expect(identical(rows.expandNode(missing), rows), isTrue);
    expect(identical(rows.collapseNode(missing), rows), isTrue);
    expect(identical(rows.reveal(missing), rows), isTrue);
    expect(identical(rows.collapseNode(file), rows), isTrue);
    const state = ExpansionState.collapsed();
    expect(identical(state.reveal(tree, missing), state), isTrue);
    expect(identical(state.expandSubtree(tree, missing), state), isTrue);
    const selection = SelectionState.empty(mode: SelectionMode.multiple);
    expect(identical(selection.check(tree, missing), selection), isTrue);
    expect(selection.checkStateOf(tree, missing), CheckState.unchecked);

    // Collapsing keeps the state of the folders below.
    final reopened = rows.collapseNode(src).collapseNode(lib).expandNode(lib);
    expect(reopened.rowOf(src)!.isExpanded, isFalse);

    // Expansion and selection states drop ids a tree no longer has.
    final pruned = ExpansionState.withExpanded([lib, missing]).prune(tree);
    expect(pruned.exceptions, {lib});
    expect(
      SelectionState(
        mode: SelectionMode.multiple,
        selected: [lib, missing],
      ).prune(tree).selected,
      {lib},
    );

    // toJson is ready for jsonEncode.
    final json = jsonEncode(ExpansionState.withExpanded([lib]).toJson());
    expect(
      ExpansionState.fromJson(jsonDecode(json) as Map<String, Object?>),
      ExpansionState.withExpanded([lib]),
    );

    // checkStates covers every node.
    expect(
      const SelectionState.empty().checkStates(tree).keys,
      tree.nodes.map((node) => node.id),
    );
    // Single mode cannot check a directory with several leaves.
    expect(
      () => const SelectionState.empty().check(tree, lib),
      throwsStateError,
    );

    // ListDiff rejects duplicate keys.
    expect(
      () => ListDiff.compute(['a', 'a'], ['a'], keyOf: (item) => item),
      throwsArgumentError,
    );

    // `remove` takes a subtree; `recursive: false` removes only the entry.
    final builder = tree.toBuilder()..addDirectory('/repo/lib');
    expect(builder.remove('/repo/lib', recursive: false), 1);
    expect(builder.remove('/repo/lib'), 2);

    // Unchanged paths keep their ids across a rebuild.
    final next = tree.rebuild((builder) => builder.addFile('/repo/new.txt'));
    expect(next[lib]!.path, tree[lib]!.path);

    // TreePath.extension is only the last extension.
    expect(TreePath.parse('/dist/app.tar.gz').extension, '.gz');

    // A case-insensitive tree keeps a display spelling.
    final folded = DirectoryTree.fromPaths([
      '/Repo/README.md',
    ], options: const TreeOptions(paths: PathPolicy.caseInsensitive));
    expect(folded.files.single.path.toString(), '/Repo/README.md');
    expect(folded.files.single.id.value, '/repo/readme.md');

    // Backslashes are ordinary characters when they are not separators.
    expect(
      const PathPolicy(backslashIsSeparator: false).parse(r'a\b').segments,
      [r'a\b'],
    );

    // An empty query matches everything, so the view skips filtering.
    expect(TreeQuery.parse('').matchesAll, isTrue);
    expect(tree.flatten(filter: TreeQuery.parse('')).filter, isNull);

    // maxDepth 0 prints only the depth-0 rows.
    expect(tree.render(maxDepth: 0), 'repo/');

    // The quick start in lib/directory_tree.dart prints these rows.
    var opened = tree.flatten(expansion: const ExpansionState.collapsed());
    opened = opened.toggleNode(opened.first.id);
    expect(
      opened.map((row) => row.label).toString(),
      '(repo, lib, test, README.md)',
    );

    // TreeDiff reports the ancestor whose parent changed, not the depth
    // shift of its descendants.
    const moved = ['/r/x/a.txt', '/r/y/b.txt'];
    final topLevel = DirectoryTree.fromPaths(moved);
    final nested = DirectoryTree.fromPaths(
      moved,
      options: const TreeOptions(roots: TreeRoots.filesystem()),
    );
    expect(topLevel.nodeAt('/r/x/a.txt')!.depth, 1);
    expect(nested.nodeAt('/r/x/a.txt')!.depth, 3);
    expect(TreeDiff.compute(topLevel, nested).changed, [
      topLevel.idOf('/r/x'),
      topLevel.idOf('/r/y'),
    ]);
  });
}

/// The tree that the README's quick start builds and later sections reuse.
DirectoryTree<Object?> _quickStartTree() => DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/main.dart',
  '/repo/test/tree_test.dart',
  '/repo/README.md',
]);

/// The `project` tree of the README's search section.
DirectoryTree<Object?> _searchProject() => DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/src/tree.g.dart',
  '/repo/lib/main.dart',
  '/repo/test/tree_test.dart',
  '/repo/docs/my notes.md',
  '/repo/dist/app.tar.gz',
  '/repo/README.md',
]);

/// A README Dart block and the ```text block that directly follows it, if
/// any.
final class _Block {
  _Block(this.code, this.output);

  /// The code between the fences.
  final String code;

  /// The text of the following ```text block without its final newline, or
  /// `null` when the next block is not a ```text block right after this one.
  final String? output;
}

/// The README's Dart blocks, and the ```text blocks that do not directly
/// follow a Dart block.
({List<_Block> dartBlocks, List<String> orphanTextBlocks}) _readmeBlocks(
  String readme,
) {
  final fences = RegExp(
    r'^```(\w*)\n([\s\S]*?)^```$',
    multiLine: true,
  ).allMatches(readme).toList();
  final dartBlocks = <_Block>[];
  final orphans = <String>[];
  for (var i = 0; i < fences.length; i++) {
    final fence = fences[i];
    final language = fence.group(1);
    if (language == 'text') {
      final previous = i > 0 ? fences[i - 1] : null;
      final attached =
          previous != null &&
          previous.group(1) == 'dart' &&
          readme.substring(previous.end, fence.start).trim().isEmpty;
      if (!attached) orphans.add(fence.group(2)!);
      continue;
    }
    if (language != 'dart') continue;
    final next = i + 1 < fences.length ? fences[i + 1] : null;
    final hasOutput =
        next != null &&
        next.group(1) == 'text' &&
        readme.substring(fence.end, next.start).trim().isEmpty;
    final output = hasOutput ? next.group(2)! : null;
    dartBlocks.add(
      _Block(
        fence.group(2)!,
        output?.substring(0, output.length - 1), // Drop the final newline.
      ),
    );
  }
  return (dartBlocks: dartBlocks, orphanTextBlocks: orphans);
}

/// The blocks that [source] checks with `helper(block('...'))`.
Set<_Block> _checkedBlocks(
  String source,
  String helper,
  _Block Function(String line) block,
) => {
  for (final match in RegExp(
    '$helper\\(block\\(([\'"])(.+?)\\1\\)\\)',
  ).allMatches(source))
    block(match.group(2)!),
};

/// Trims every line, collapses inner whitespace, and drops blank lines, so
/// indentation inside a test does not hide a copied block.
String _normalize(String code) => code
    .split('\n')
    .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((line) => line.isNotEmpty)
    .join('\n');

/// A `print(...); // output` line; group 1 is the promised output.
final _printLine = RegExp(r'^\s*print\(.*\);\s*// (.*)$', multiLine: true);

/// The outputs that `print(...); // output` lines in [block] promise.
List<String> _expectedPrints(_Block block) => [
  for (final match in _printLine.allMatches(block.code)) match.group(1)!,
];

/// The output that the ```text block after [block] shows.
String _expectedOutput(_Block block) => block.output!;

/// Runs [body] and returns everything it printed, one entry per `print`.
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
