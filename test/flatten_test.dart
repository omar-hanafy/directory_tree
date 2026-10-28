import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/src/view/expansion_state.dart';
import 'package:directory_tree/src/view/tree_rows.dart';
import 'package:test/test.dart';

/// Hand-checked tree (case sensitive, minimal roots, directories first):
///
/// ```text
/// 0 /other            (inferred)
/// 1   q.md
/// 2 /r                (inferred)
/// 3   a               (inferred)
/// 4     x.txt
/// 5     y.txt
/// 6   b               (explicit directory entry)
/// 7     c             (inferred)
/// 8       z.txt
/// 9   top.txt
/// ```
DirectoryTree<int> sampleTree() => DirectoryTree<int>.build([
  const TreeEntry.file('/r/a/x.txt', data: 1),
  const TreeEntry.file('/r/a/y.txt', data: 2),
  const TreeEntry.directory('/r/b', data: 3),
  const TreeEntry.file('/r/b/c/z.txt', data: 4),
  const TreeEntry.file('/r/top.txt', data: 5),
  const TreeEntry.file('/other/q.md', data: 6),
]);

/// One row as `label|depth|flags|guides`.
///
/// Flags, in order: `E` expanded, `C` has children, `L` is last, `M` is a
/// match; `-` when false. Guides: one digit per level, `1` where a guide
/// line continues.
String describe(TreeRow<Object?> row) {
  final flags = [
    if (row.isExpanded) 'E' else '-',
    if (row.hasChildren) 'C' else '-',
    if (row.isLast) 'L' else '-',
    if (row.isMatch) 'M' else '-',
  ].join();
  final guides = row.guides.map((guide) => guide ? '1' : '0').join();
  return '${row.label}|${row.depth}|$flags|$guides';
}

List<String> table(List<TreeRow<Object?>> rows) => rows.map(describe).toList();

NodeId id(String path) => NodeId(path);

TreeFilter nameFilter(bool Function(String name) test) =>
    TreeFilter.where<Object?>((node) => test(node.name));

void main() {
  final tree = sampleTree();

  group('without a filter', () {
    test('everything expanded (the default)', () {
      final rows = tree.flatten();
      expect(table(rows), [
        'other|0|EC-M|',
        'q.md|1|--LM|1',
        'r|0|ECLM|',
        'a|1|EC-M|0',
        'x.txt|2|---M|01',
        'y.txt|2|--LM|01',
        'b|1|EC-M|0',
        'c|2|ECLM|01',
        'z.txt|3|--LM|010',
        'top.txt|1|--LM|0',
      ]);
      expect(rows.map((row) => row.node), tree.nodes);
      expect(rows.map((row) => row.id), tree.nodes.map((node) => node.id));
      expect(rows.expansion, const ExpansionState.expanded());
      expect(rows.filter, isNull);
      expect(rows.compactFolders, isFalse);
      expect(identical(rows.tree, tree), isTrue);
    });

    test('everything collapsed shows the top-level rows', () {
      final rows = tree.flatten(expansion: const ExpansionState.collapsed());
      expect(table(rows), ['other|0|-C-M|', 'r|0|-CLM|']);
    });

    test('mixed expansion', () {
      final rows = tree.flatten(
        expansion: ExpansionState.withExpanded([id('/r'), id('/r/b')]),
      );
      expect(table(rows), [
        'other|0|-C-M|',
        'r|0|ECLM|',
        'a|1|-C-M|0',
        'b|1|EC-M|0',
        'c|2|-CLM|01',
        'top.txt|1|--LM|0',
      ]);
    });

    test('states of hidden directories and of files do not matter', () {
      final rows = tree.flatten(
        expansion: ExpansionState.withExpanded([
          id('/r/b/c'),
          id('/r/a/x.txt'),
          id('/nowhere'),
        ]),
      );
      expect(table(rows), ['other|0|-C-M|', 'r|0|-CLM|']);
      expect(rows[0].isExpanded, isFalse);
    });

    test('rows of files are never expanded', () {
      final rows = tree.flatten(
        expansion: ExpansionState.withCollapsed([id('/r/a')]),
      );
      final file = rows.rowOf(id('/r/top.txt'))!;
      expect(file.isExpanded, isFalse);
      expect(file.hasChildren, isFalse);
      expect(rows.rowOf(id('/r/a'))!.isExpanded, isFalse);
      expect(rows.rowOf(id('/r/a/x.txt')), isNull);
    });

    test('an explicit empty directory has no children', () {
      final empty = DirectoryTree.fromPaths(['/p/empty/', '/p/f.txt']);
      expect(table(empty.flatten()), [
        'p|0|ECLM|',
        'empty|1|E--M|0',
        'f.txt|1|--LM|0',
      ]);
    });

    test('an empty tree has no rows', () {
      final empty = DirectoryTree<int>.empty();
      final rows = empty.flatten(filter: nameFilter((name) => true));
      expect(rows, isEmpty);
      expect(empty.flatten(compactFolders: true), isEmpty);
    });

    test('a matchesAll filter counts as no filter', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: TreeFilter.all,
      );
      expect(rows.filter, isNull);
      expect(rows.expansion, const ExpansionState.collapsed());
      expect(table(rows), ['other|0|-C-M|', 'r|0|-CLM|']);
      final combined = nameFilter((name) => false).or(TreeFilter.all);
      expect(tree.flatten(filter: combined).filter, isNull);
    });
  });

  group('with a filter', () {
    final textFiles = nameFilter((name) => name.endsWith('.txt'));

    test('keeps matches and their ancestors, revealing the matches', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
      );
      expect(table(rows), [
        'r|0|ECL-|',
        'a|1|EC--|0',
        'x.txt|2|---M|01',
        'y.txt|2|--LM|01',
        'b|1|EC--|0',
        'c|2|ECL-|01',
        'z.txt|3|--LM|010',
        'top.txt|1|--LM|0',
      ]);
      expect(rows.filter, same(textFiles));
      expect(
        rows.expansion,
        ExpansionState.withExpanded([
          id('/r'),
          id('/r/a'),
          id('/r/b'),
          id('/r/b/c'),
        ]),
      );
    });

    test('hidden siblings do not count for isLast and hasChildren', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: nameFilter((name) => name == 'y.txt'),
      );
      expect(table(rows), ['r|0|ECL-|', 'a|1|ECL-|0', 'y.txt|2|--LM|00']);
    });

    test('expandMatches false keeps the given expansion', () {
      const collapsed = ExpansionState.collapsed();
      final rows = tree.flatten(
        expansion: collapsed,
        filter: textFiles,
        expandMatches: false,
      );
      expect(table(rows), ['r|0|-CL-|']);
      expect(identical(rows.expansion, collapsed), isTrue);
      final partly = tree.flatten(
        expansion: ExpansionState.withExpanded([id('/r'), id('/r/b')]),
        filter: textFiles,
        expandMatches: false,
      );
      expect(table(partly), [
        'r|0|ECL-|',
        'a|1|-C--|0',
        'b|1|EC--|0',
        'c|2|-CL-|01',
        'top.txt|1|--LM|0',
      ]);
    });

    test('revealing keeps directories the user collapsed elsewhere', () {
      final rows = tree.flatten(
        expansion: ExpansionState.withCollapsed([id('/r/a'), id('/other')]),
        filter: nameFilter((name) => name == 'z.txt' || name == 'q.md'),
      );
      // /r/a has no match, so it stays collapsed; /other is an ancestor of
      // q.md and is revealed.
      expect(rows.expansion, ExpansionState.withCollapsed([id('/r/a')]));
      expect(table(rows), [
        'other|0|EC--|',
        'q.md|1|--LM|1',
        'r|0|ECL-|',
        'b|1|ECL-|0',
        'c|2|ECL-|00',
        'z.txt|3|--LM|000',
      ]);
    });

    test('a matching directory without matching children', () {
      final rows = tree.flatten(filter: nameFilter((name) => name == 'b'));
      expect(table(rows), ['r|0|ECL-|', 'b|1|E-LM|0']);
    });

    test('a match with a matching descendant', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: nameFilter((name) => name == 'r' || name == 'z.txt'),
      );
      expect(table(rows), [
        'r|0|ECLM|',
        'b|1|ECL-|0',
        'c|2|ECL-|00',
        'z.txt|3|--LM|000',
      ]);
    });

    test('a filter that matches nothing gives no rows', () {
      final rows = tree.flatten(filter: nameFilter((name) => false));
      expect(rows, isEmpty);
      expect(rows.expansion, const ExpansionState.expanded());
    });

    test('a typed filter on another data type matches nothing', () {
      final rows = tree.flatten(
        filter: TreeFilter.where<String>((node) => true),
      );
      expect(rows, isEmpty);
    });

    test('the filter is called exactly once per node', () {
      var calls = 0;
      final counting = TreeFilter.where<Object?>((node) {
        calls++;
        return node.isFile;
      });
      final rows = tree.flatten(filter: counting);
      expect(calls, tree.length);
      expect(rows, hasLength(tree.length));
    });
  });

  group('compact folders', () {
    test('a single-child directory chain shares a row', () {
      final rows = tree.flatten(compactFolders: true);
      expect(table(rows), [
        'other|0|EC-M|',
        'q.md|1|--LM|1',
        'r|0|ECLM|',
        'a|1|EC-M|0',
        'x.txt|2|---M|01',
        'y.txt|2|--LM|01',
        'b/c|1|EC-M|0',
        'z.txt|2|--LM|01',
        'top.txt|1|--LM|0',
      ]);
      final chain = rows[6];
      expect(chain.chain.map((node) => node.name), ['b', 'c']);
      expect(chain.node.id, id('/r/b/c'));
      expect(chain.id, id('/r/b/c'));
      expect(rows[0].chain, [rows[0].node]);
      expect(rows.compactFolders, isTrue);
    });

    test('the row expands as its deepest directory', () {
      final intermediateCollapsed = tree.flatten(
        expansion: ExpansionState.withCollapsed([id('/r/b')]),
        compactFolders: true,
      );
      expect(describe(intermediateCollapsed[6]), 'b/c|1|EC-M|0');
      expect(describe(intermediateCollapsed[7]), 'z.txt|2|--LM|01');
      final nodeCollapsed = tree.flatten(
        expansion: ExpansionState.withCollapsed([id('/r/b/c')]),
        compactFolders: true,
      );
      expect(table(nodeCollapsed).sublist(6), [
        'b/c|1|-C-M|0',
        'top.txt|1|--LM|0',
      ]);
    });

    test('long chains, empty leaves, and single files', () {
      final chains = DirectoryTree.fromPaths([
        '/p/',
        '/p/a/b/c/d/f.txt',
        '/q/',
        '/q/only/',
        '/s/one.txt',
      ]);
      expect(table(chains.flatten(compactFolders: true)), [
        'p/a/b/c/d|0|EC-M|',
        'f.txt|1|--LM|1',
        'q/only|0|E--M|',
        's|0|ECLM|',
        'one.txt|1|--LM|0',
      ]);
    });

    test('compaction ignores the filter', () {
      final bMatches = tree.flatten(
        filter: nameFilter((name) => name == 'b'),
        compactFolders: true,
      );
      expect(table(bMatches), ['r|0|ECL-|', 'b/c|1|E-LM|0']);
      final deepMatches = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: nameFilter((name) => name == 'z.txt'),
        compactFolders: true,
      );
      expect(table(deepMatches), [
        'r|0|ECL-|',
        'b/c|1|ECL-|0',
        'z.txt|2|--LM|00',
      ]);
    });

    test('labels join without doubling the root separator', () {
      const filesystem = TreeOptions(roots: TreeRoots.filesystem());
      final posix = DirectoryTree.fromPaths([
        '/usr/lib/x.so',
        '/usr/lib/y.so',
      ], options: filesystem);
      expect(table(posix.flatten(compactFolders: true)), [
        '/usr/lib|0|ECLM|',
        'x.so|1|---M|0',
        'y.so|1|--LM|0',
      ]);
      expect(posix.flatten().first.label, '/');
      final roots = DirectoryTree.fromPaths([
        'C:/Users/me/a.txt',
        '//nas/share/docs/b.txt',
        'rel/x/c.txt',
      ], options: filesystem);
      expect(roots.flatten(compactFolders: true).map((row) => row.label), [
        './rel/x',
        'c.txt',
        '//nas/share/docs',
        'b.txt',
        'C:/Users/me',
        'a.txt',
      ]);
    });
  });

  group('labels', () {
    test('colliding top-level names keep their disambiguated labels', () {
      final colliding = DirectoryTree.fromPaths([
        '/x/a/src/lib/f.dart',
        '/x/a/src/g.dart',
        '/y/b/src/h.dart',
      ]);
      expect(colliding.flatten().map((row) => row.label), [
        'a/src',
        'lib',
        'f.dart',
        'g.dart',
        'b/src',
        'h.dart',
      ]);
      final compacted = DirectoryTree.fromPaths([
        '/x/a/src/',
        '/x/a/src/lib/f.dart',
        '/y/b/src/h.dart',
      ]);
      expect(compacted.flatten(compactFolders: true).map((row) => row.label), [
        'a/src/lib',
        'f.dart',
        'b/src',
        'h.dart',
      ]);
    });
  });

  group('deep trees', () {
    const depth = 1000;
    final segments = [for (var i = 0; i < depth; i++) 'd$i'];
    final deepTree = DirectoryTree.fromPaths([
      '/${segments.first}/',
      '/${segments.join('/')}/leaf.txt',
    ]);

    test('a $depth-deep chain flattens without recursion', () {
      expect(deepTree.length, depth + 1);
      final rows = deepTree.flatten();
      expect(rows, hasLength(depth + 1));
      final leaf = rows.last;
      expect(leaf.depth, depth);
      expect(leaf.guides, hasLength(depth));
      expect(leaf.guides.every((guide) => !guide), isTrue);
      expect(rows.every((row) => row.isLast), isTrue);
      expect(rows.parentIndexOf(depth), depth - 1);
      expect(rows.indexOfNode(leaf.id), depth);
    });

    test('a $depth-deep chain compacts into one row', () {
      final rows = deepTree.flatten(compactFolders: true);
      expect(rows, hasLength(2));
      expect(rows.first.chain, hasLength(depth));
      expect(rows.first.label, segments.join('/'));
      expect(rows.last.depth, 1);
      final middle = deepTree.idOf('/${segments.take(500).join('/')}')!;
      expect(rows.indexOfNode(middle), 0);
    });

    test('a $depth-deep chain filters and reveals', () {
      final rows = deepTree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: nameFilter((name) => name == 'leaf.txt'),
      );
      expect(rows, hasLength(depth + 1));
      expect(rows.expansion.exceptions, hasLength(depth));
      expect(rows.where((row) => row.isMatch), [rows.last]);
    });
  });

  group('agrees with a definitional oracle', () {
    for (var seed = 0; seed < 150; seed++) {
      test('random tree $seed', () {
        final random = Random(seed);
        final tree = randomTree(random);
        for (final compactFolders in const [false, true]) {
          for (final filtered in const [false, true]) {
            final filter = filtered ? randomFilter(random, tree) : null;
            final expansion = randomExpansion(random, tree);
            final expandMatches = random.nextBool();
            final rows = tree.flatten(
              expansion: expansion,
              filter: filter,
              expandMatches: expandMatches,
              compactFolders: compactFolders,
            );
            final expected = oracleFlatten(
              tree,
              expansion: expansion,
              filter: filter,
              expandMatches: expandMatches,
              compactFolders: compactFolders,
            );
            expectRows(
              rows,
              expected,
              'seed $seed, compact $compactFolders, filter $filtered, '
              'expandMatches $expandMatches',
            );
          }
        }
      });
    }
  });
}

/// A row as the contract defines it, computed without the implementation.
typedef ExpectedRow = ({
  List<NodeId> chain,
  int depth,
  bool isExpanded,
  bool hasChildren,
  bool isLast,
  List<bool> guides,
  String label,
  bool isMatch,
});

/// Flattens by the definitions in the contract, recursively and naively:
/// visibility by scanning descendants, revealing by [ExpansionState.reveal],
/// chains by [DirectoryTree.childrenOf].
({List<ExpectedRow> rows, ExpansionState expansion}) oracleFlatten(
  DirectoryTree<Object?> tree, {
  required ExpansionState expansion,
  required TreeFilter? filter,
  required bool expandMatches,
  required bool compactFolders,
}) {
  final active = filter == null || filter.matchesAll ? null : filter;
  bool matches(TreeNode<Object?> node) =>
      active == null || active.matches(node);
  bool visible(TreeNode<Object?> node) =>
      active == null ||
      matches(node) ||
      tree.descendantsOf(node.id).any(matches);
  var state = expansion;
  if (active != null && expandMatches) {
    for (final node in tree.nodes) {
      if (matches(node)) state = state.reveal(tree, node.id);
    }
  }
  final rows = <ExpectedRow>[];
  void emit(List<TreeNode<Object?>> candidates, int depth, List<bool> guides) {
    final shown = candidates.where(visible).toList();
    for (var i = 0; i < shown.length; i++) {
      final chain = <TreeNode<Object?>>[shown[i]];
      while (compactFolders && chain.last.isDirectory) {
        final children = tree.childrenOf(chain.last.id);
        if (children.length != 1 || !children.single.isDirectory) break;
        chain.add(children.single);
      }
      final node = chain.last;
      final isExpanded = node.isDirectory && state.isExpanded(node.id);
      final isLast = i == shown.length - 1;
      rows.add((
        chain: [for (final member in chain) member.id],
        depth: depth,
        isExpanded: isExpanded,
        hasChildren: tree.childrenOf(node.id).any(visible),
        isLast: isLast,
        guides: guides,
        label: joinLabels(chain),
        isMatch: chain.any(matches),
      ));
      if (isExpanded) {
        emit(tree.childrenOf(node.id), depth + 1, [...guides, !isLast]);
      }
    }
  }

  emit(tree.rootNodes, 0, const []);
  return (rows: rows, expansion: state);
}

String joinLabels(List<TreeNode<Object?>> chain) {
  var label = chain.first.label;
  for (final member in chain.skip(1)) {
    label = label.endsWith('/')
        ? '$label${member.label}'
        : '$label/${member.label}';
  }
  return label;
}

void expectRows(
  TreeRows<Object?> rows,
  ({List<ExpectedRow> rows, ExpansionState expansion}) expected,
  String reason,
) {
  expect(rows.expansion, expected.expansion, reason: reason);
  expect(
    rows.map(describe).toList(),
    expected.rows.map(describeExpected).toList(),
    reason: reason,
  );
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final want = expected.rows[i];
    expect(
      row.chain.map((node) => node.id).toList(),
      want.chain,
      reason: '$reason, row $i',
    );
    expect(row.id, want.chain.last, reason: '$reason, row $i');
    expect(identical(row.node, row.chain.last), isTrue);
  }
}

String describeExpected(ExpectedRow row) {
  final flags = [
    if (row.isExpanded) 'E' else '-',
    if (row.hasChildren) 'C' else '-',
    if (row.isLast) 'L' else '-',
    if (row.isMatch) 'M' else '-',
  ].join();
  final guides = row.guides.map((guide) => guide ? '1' : '0').join();
  return '${row.label}|${row.depth}|$flags|$guides';
}

const _rootPrefixes = ['/r', '/s/t', 'C:/w', '//nas/share', 'rel', '/'];
const _names = ['a', 'b', 'lib', 'src', 'x.txt', 'y.md', 'z'];

/// A random tree of up to 40 entries under several kinds of path roots,
/// with repeated names (so conflicts, merges, and single-child chains are
/// common) and a random [TreeRoots] strategy.
DirectoryTree<int> randomTree(Random random) {
  final count = 1 + random.nextInt(40);
  final entries = <TreeEntry<int>>[];
  for (var i = 0; i < count; i++) {
    final segments = <String>[];
    if (random.nextInt(5) == 0) {
      // A long run of unique names makes compactable chains likely.
      segments.addAll(['p', 'q', 'u', 'v'].take(1 + random.nextInt(4)));
    }
    final extra = random.nextInt(5);
    for (var d = 0; d < extra; d++) {
      segments.add(_names[random.nextInt(_names.length)]);
    }
    final prefix = _rootPrefixes[random.nextInt(_rootPrefixes.length)];
    final path = segments.isEmpty
        ? prefix
        : prefix.endsWith('/')
        ? '$prefix${segments.join('/')}'
        : '$prefix/${segments.join('/')}';
    entries.add(
      random.nextInt(4) == 0
          ? TreeEntry<int>.directory(path, data: i)
          : TreeEntry<int>.file(path, data: i),
    );
  }
  const strategies = [
    TreeRoots.minimal(),
    TreeRoots.commonAncestor(),
    TreeRoots.filesystem(),
  ];
  return DirectoryTree<int>.build(
    entries,
    options: TreeOptions(roots: strategies[random.nextInt(strategies.length)]),
  );
}

/// One of several filter shapes: a random id subset, a name test, all
/// directories, one extension, or nothing at all.
TreeFilter randomFilter(Random random, DirectoryTree<Object?> tree) {
  switch (random.nextInt(5)) {
    case 0:
      final chosen = {
        for (final node in tree.nodes)
          if (random.nextInt(5) == 0) node.id,
      };
      return TreeFilter.where<Object?>((node) => chosen.contains(node.id));
    case 1:
      final letter = 'abxyz'[random.nextInt(5)];
      return TreeFilter.where<Object?>((node) => node.name.contains(letter));
    case 2:
      return TreeFilter.where<Object?>((node) => node.isDirectory);
    case 3:
      return TreeFilter.where<Object?>((node) => node.path.extension == '.md');
    default:
      return TreeFilter.where<Object?>((node) => false);
  }
}

/// A random state over random node ids (files and an unknown id included).
ExpansionState randomExpansion(Random random, DirectoryTree<Object?> tree) {
  final ids = [
    for (final node in tree.nodes)
      if (random.nextInt(3) == 0) node.id,
    const NodeId('/unknown'),
  ];
  return random.nextBool()
      ? ExpansionState.withExpanded(ids)
      : ExpansionState.withCollapsed(ids);
}
