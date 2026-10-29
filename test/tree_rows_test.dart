import 'dart:convert';
import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
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

/// One row as `label|depth|flags|guides`: flags `E` expanded, `C` has
/// children, `L` last, `M` match (`-` when false); guides `1` where a guide
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

const other = NodeId('/other');
const q = NodeId('/other/q.md');
const r = NodeId('/r');
const a = NodeId('/r/a');
const b = NodeId('/r/b');
const c = NodeId('/r/b/c');
const z = NodeId('/r/b/c/z.txt');
const top = NodeId('/r/top.txt');
const unknown = NodeId('/nowhere');

final textFiles = TreeFilter.where<Object?>(
  (node) => node.name.endsWith('.txt'),
);

/// Options with the single fixed root `/r`.
const fixedR = TreeOptions(roots: TreeRoots.fixed(['/r']));

void main() {
  final tree = sampleTree();

  group('list behavior', () {
    test('is a list of the visible rows', () {
      final rows = tree.flatten();
      expect(rows, isA<List<TreeRow<int>>>());
      expect(rows, hasLength(10));
      expect(rows.first.label, 'other');
      expect(rows[2].label, 'r');
      expect(rows.last.label, 'top.txt');
      expect(rows.sublist(0, 2).map((row) => row.label), ['other', 'q.md']);
      expect(rows.reversed.first.label, 'top.txt');
      expect(rows.where((row) => row.node.isFile), hasLength(5));
      expect(rows.indexOf(rows[3]), 3);
      expect(rows.toList()..add(rows.first), hasLength(11));
      expect(() => rows[10], throwsRangeError);
      expect(() => rows[-1], throwsRangeError);
    });

    test('every mutator throws, even when it would change nothing', () {
      for (final rows in [
        tree.flatten(),
        DirectoryTree<int>.empty().flatten(),
      ]) {
        final row = tree.flatten().first;
        final mutations = <String, void Function()>{
          '[]=': () => rows[0] = row,
          'length=': () => rows.length = 0,
          'first=': () => rows.first = row,
          'last=': () => rows.last = row,
          'add': () => rows.add(row),
          'addAll': () => rows.addAll(const []),
          'insert': () => rows.insert(0, row),
          'insertAll': () => rows.insertAll(0, const []),
          'setAll': () => rows.setAll(0, const []),
          'remove': () => rows.remove(row),
          'removeAt': () => rows.removeAt(0),
          'removeLast': () => rows.removeLast(),
          'removeWhere': () => rows.removeWhere((_) => false),
          'retainWhere': () => rows.retainWhere((_) => true),
          'removeRange': () => rows.removeRange(0, 0),
          'setRange': () => rows.setRange(0, 0, const []),
          'replaceRange': () => rows.replaceRange(0, 0, const []),
          'fillRange': () => rows.fillRange(0, 0),
          'sort': () => rows.sort(),
          'shuffle': () => rows.shuffle(),
          'clear': rows.clear,
        };
        final length = rows.length;
        mutations.forEach((name, mutate) {
          expect(mutate, throwsUnsupportedError, reason: name);
        });
        expect(rows, hasLength(length));
      }
    });

    test('rows expose unmodifiable chain and guides lists', () {
      final rows = tree.flatten(compactFolders: true);
      final chained = rows.rowOf(c)!;
      expect(() => chained.chain.add(chained.node), throwsUnsupportedError);
      expect(() => chained.guides[0] = true, throwsUnsupportedError);
      final single = rows.first;
      expect(() => single.chain.clear(), throwsUnsupportedError);
      expect(() => single.guides.add(true), throwsUnsupportedError);
    });
  });

  group('rows as values', () {
    test('rows of separate flattens are equal but not identical', () {
      final first = tree.flatten(compactFolders: true);
      final second = tree.flatten(compactFolders: true);
      for (var i = 0; i < first.length; i++) {
        expect(identical(first[i], second[i]), isFalse);
        expect(first[i], second[i]);
        expect(first[i].hashCode, second[i].hashCode);
      }
    });

    test('rows differ when any visible property differs', () {
      final plain = tree.flatten();
      final filtered = tree.flatten(
        filter: TreeFilter.where<Object?>(
          (node) => node.name == 'y.txt' || node.name == 'z.txt',
        ),
      );
      // a: same node and depth, but not a match under the filter.
      expect(describe(plain.rowOf(a)!), 'a|1|EC-M|0');
      expect(describe(filtered.rowOf(a)!), 'a|1|EC--|0');
      expect(plain.rowOf(a) == filtered.rowOf(a), isFalse);
      // b: last only because the filter hides top.txt.
      expect(plain.rowOf(b)!.isLast, isFalse);
      expect(filtered.rowOf(b)!.isLast, isTrue);
      expect(plain.rowOf(b) == filtered.rowOf(b), isFalse);
      // z.txt: same flags; the guides differ because b became last.
      final plainLeaf = plain.rowOf(z)!;
      final filteredLeaf = filtered.rowOf(z)!;
      expect(describe(plainLeaf), 'z.txt|3|--LM|010');
      expect(describe(filteredLeaf), 'z.txt|3|--LM|000');
      expect(plainLeaf == filteredLeaf, isFalse);
      // A compacted row differs from the plain row of its node.
      final compacted = tree.flatten(compactFolders: true).rowOf(c)!;
      expect(compacted == plain.rowOf(c), isFalse);
      // Expansion state.
      final collapsed = plain.collapseNode(a);
      expect(collapsed.rowOf(a) == plain.rowOf(a), isFalse);
      expect(plain.rowOf(a) == plain.rowOf(a), isTrue);
      expect(plain.first == Object(), isFalse);
    });

    test('toString lists the label, depth, true flags, and guides', () {
      final rows = tree.flatten();
      expect(
        rows.first.toString(),
        'TreeRow(other, depth: 0, expanded, children, match, guides: [])',
      );
      expect(
        rows.rowOf(z).toString(),
        'TreeRow(z.txt, depth: 3, last, match, guides: [false, true, false])',
      );
      final hidden = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
        expandMatches: false,
      );
      expect(
        hidden.single.toString(),
        'TreeRow(r, depth: 0, children, last, '
        'guides: [])',
      );
    });
  });

  group('lookup and keyboard navigation', () {
    test('indexOfNode and rowOf on visible, hidden, and unknown ids', () {
      final rows = tree.flatten(expansion: ExpansionState.withCollapsed([a]));
      expect(rows.indexOfNode(other), 0);
      expect(rows.indexOfNode(r), 2);
      expect(rows.indexOfNode(a), 3);
      expect(rows.indexOfNode(b), 4);
      expect(rows.indexOfNode(top), 7);
      expect(rows.indexOfNode(const NodeId('/r/a/x.txt')), -1);
      expect(rows.indexOfNode(unknown), -1);
      expect(rows.rowOf(b)!.label, 'b');
      expect(rows.rowOf(const NodeId('/r/a/x.txt')), isNull);
      expect(rows.rowOf(unknown), isNull);
    });

    test('nodes hidden by the filter are not found', () {
      final rows = tree.flatten(filter: textFiles);
      expect(rows.indexOfNode(other), -1);
      expect(rows.indexOfNode(q), -1);
      expect(rows.indexOfNode(r), 0);
      expect(rows.indexOfNode(top), rows.length - 1);
    });

    test('ids inside a compacted row find that row', () {
      final rows = tree.flatten(compactFolders: true);
      expect(rows.indexOfNode(b), 6);
      expect(rows.indexOfNode(c), 6);
      expect(rows.rowOf(b)!.id, c);
      expect(rows.indexOfNode(z), 7);
      final deep = DirectoryTree.fromPaths(['/p/', '/p/a/b/c/f.txt']);
      final chained = deep.flatten(compactFolders: true);
      for (final path in ['/p', '/p/a', '/p/a/b', '/p/a/b/c']) {
        expect(chained.indexOfNode(NodeId(path)), 0, reason: path);
      }
      expect(chained.indexOfNode(const NodeId('/p/a/b/c/f.txt')), 1);
    });

    test('a compacted row finds the directories it shows that the filter '
        'hides', () {
      // src neither matches nor contains a match, yet the row lib/src shows
      // it, because compaction follows the tree, not the filter.
      final workspace = DirectoryTree.fromPaths([
        '/r/lib/src/x.txt',
        '/r/other.md',
      ], options: fixedR);
      final lib = workspace.idOf('/r/lib')!;
      final src = workspace.idOf('/r/lib/src')!;
      final libOnly = TreeFilter.where<Object?>((node) => node.name == 'lib');
      final compacted = workspace.flatten(
        filter: libOnly,
        compactFolders: true,
      );
      expect(table(compacted), ['r|0|ECL-|', 'lib/src|1|E-LM|0']);
      expect(compacted.indexOfNode(lib), 1);
      expect(compacted.indexOfNode(src), 1);
      expect(compacted.rowOf(src)!.id, src);
      // Without compaction the filter hides src.
      final plain = workspace.flatten(filter: libOnly);
      expect(table(plain), ['r|0|ECL-|', 'lib|1|E-LM|0']);
      expect(plain.indexOfNode(src), -1);
      expect(plain.rowOf(src), isNull);
    });

    test('parentIndexOf and firstChildIndexOf', () {
      final rows = tree.flatten();
      expect(
        [for (var i = 0; i < rows.length; i++) rows.parentIndexOf(i)],
        [null, 0, null, 2, 3, 3, 2, 6, 7, 2],
      );
      expect(
        [for (var i = 0; i < rows.length; i++) rows.firstChildIndexOf(i)],
        [1, null, 3, 4, null, null, 7, 8, null, null],
      );
    });

    test('keyboard helpers with compaction and collapsed rows', () {
      final rows = tree.flatten(
        expansion: ExpansionState.withCollapsed([a]),
        compactFolders: true,
      );
      expect(table(rows), [
        'other|0|EC-M|',
        'q.md|1|--LM|1',
        'r|0|ECLM|',
        'a|1|-C-M|0',
        'b/c|1|EC-M|0',
        'z.txt|2|--LM|01',
        'top.txt|1|--LM|0',
      ]);
      expect(
        [for (var i = 0; i < rows.length; i++) rows.parentIndexOf(i)],
        [null, 0, null, 2, 2, 4, 2],
      );
      expect(
        [for (var i = 0; i < rows.length; i++) rows.firstChildIndexOf(i)],
        [1, null, 3, null, 5, null, null],
      );
    });

    test('out-of-range indexes throw RangeError', () {
      final rows = tree.flatten();
      expect(() => rows.parentIndexOf(-1), throwsRangeError);
      expect(() => rows.parentIndexOf(10), throwsRangeError);
      expect(() => rows.firstChildIndexOf(10), throwsRangeError);
      final empty = DirectoryTree<int>.empty().flatten();
      expect(() => empty.parentIndexOf(0), throwsRangeError);
      expect(() => empty.firstChildIndexOf(0), throwsRangeError);
      expect(empty.indexOfNode(r), -1);
    });
  });

  group('incremental updates', () {
    test('expanding a visible row inserts its visible descendants', () {
      final collapsed = tree.flatten(
        expansion: const ExpansionState.collapsed(),
      );
      final expanded = collapsed.expandNode(r);
      expect(table(expanded), [
        'other|0|-C-M|',
        'r|0|ECLM|',
        'a|1|-C-M|0',
        'b|1|-C-M|0',
        'top.txt|1|--LM|0',
      ]);
      expect(identical(expanded[0], collapsed[0]), isTrue);
      expect(identical(expanded[1], collapsed[1]), isFalse);
      expect(expanded.expansion, ExpansionState.withExpanded([r]));
    });

    test('expanding restores descendants with their own state', () {
      final rows = tree.flatten(expansion: ExpansionState.withExpanded([b, c]));
      expect(table(rows), ['other|0|-C-M|', 'r|0|-CLM|']);
      expect(table(rows.expandNode(r)), [
        'other|0|-C-M|',
        'r|0|ECLM|',
        'a|1|-C-M|0',
        'b|1|EC-M|0',
        'c|2|ECLM|01',
        'z.txt|3|--LM|010',
        'top.txt|1|--LM|0',
      ]);
    });

    test('collapsing removes the block and reuses every other row', () {
      final rows = tree.flatten();
      final collapsed = rows.collapseNode(a);
      expect(table(collapsed), [
        'other|0|EC-M|',
        'q.md|1|--LM|1',
        'r|0|ECLM|',
        'a|1|-C-M|0',
        'b|1|EC-M|0',
        'c|2|ECLM|01',
        'z.txt|3|--LM|010',
        'top.txt|1|--LM|0',
      ]);
      for (var i = 0; i < 3; i++) {
        expect(identical(collapsed[i], rows[i]), isTrue, reason: '$i');
      }
      expect(identical(collapsed[3], rows[3]), isFalse);
      for (var i = 4; i < collapsed.length; i++) {
        expect(identical(collapsed[i], rows[i + 2]), isTrue, reason: '$i');
      }
      expect(collapsed.expansion, ExpansionState.withCollapsed([a]));
    });

    test('collapsing a top-level row', () {
      final rows = tree.flatten();
      final collapsed = rows.collapseNode(r);
      expect(table(collapsed), ['other|0|EC-M|', 'q.md|1|--LM|1', 'r|0|-CLM|']);
      expect(identical(collapsed[0], rows[0]), isTrue);
      expect(identical(collapsed[1], rows[1]), isTrue);
      final first = rows.collapseNode(other);
      expect(table(first).take(2), ['other|0|-C-M|', 'r|0|ECLM|']);
      for (var i = 1; i < first.length; i++) {
        expect(identical(first[i], rows[i + 1]), isTrue, reason: '$i');
      }
    });

    test('toggling twice restores equal rows', () {
      final rows = tree.flatten(compactFolders: true);
      for (final id in [other, r, a, b, c]) {
        final twice = rows.toggleNode(id).toggleNode(id);
        expect(twice, rows, reason: '$id');
        expect(twice.expansion, rows.expansion, reason: '$id');
      }
    });

    test('unknown ids, files, and unchanged states return the same rows', () {
      final rows = tree.flatten(expansion: ExpansionState.withCollapsed([a]));
      expect(identical(rows.expandNode(unknown), rows), isTrue);
      expect(identical(rows.collapseNode(unknown), rows), isTrue);
      expect(identical(rows.toggleNode(unknown), rows), isTrue);
      expect(identical(rows.toggleNode(top), rows), isTrue);
      expect(identical(rows.expandNode(z), rows), isTrue);
      expect(identical(rows.expandNode(r), rows), isTrue);
      expect(identical(rows.collapseNode(a), rows), isTrue);
      // Hidden directories that already have the requested state.
      final collapsed = tree.flatten(
        expansion: const ExpansionState.collapsed(),
      );
      expect(collapsed.indexOfNode(c), -1);
      expect(identical(collapsed.collapseNode(c), collapsed), isTrue);
      expect(identical(collapsed.collapseNode(a), collapsed), isTrue);
    });

    test('a hidden directory only changes the expansion', () {
      final rows = tree.flatten(expansion: const ExpansionState.collapsed());
      final changed = rows.expandNode(a);
      expect(identical(changed, rows), isFalse);
      expect(changed.expansion, ExpansionState.withExpanded([a]));
      expect(changed, hasLength(rows.length));
      for (var i = 0; i < rows.length; i++) {
        expect(identical(changed[i], rows[i]), isTrue);
      }
      // The state shows once the parent opens.
      expect(table(changed.expandNode(r)), [
        'other|0|-C-M|',
        'r|0|ECLM|',
        'a|1|EC-M|0',
        'x.txt|2|---M|01',
        'y.txt|2|--LM|01',
        'b|1|-C-M|0',
        'top.txt|1|--LM|0',
      ]);
    });

    test('a directory hidden by the filter only changes the expansion', () {
      final rows = tree.flatten(filter: textFiles);
      final changed = rows.collapseNode(other);
      expect(changed.expansion, ExpansionState.withCollapsed([other]));
      for (var i = 0; i < rows.length; i++) {
        expect(identical(changed[i], rows[i]), isTrue);
      }
    });

    test('ids inside a compacted row act on the deepest directory', () {
      final rows = tree.flatten(compactFolders: true);
      final collapsed = rows.collapseNode(b);
      expect(collapsed.expansion, ExpansionState.withCollapsed([c]));
      expect(table(collapsed).sublist(6), ['b/c|1|-C-M|0', 'top.txt|1|--LM|0']);
      expect(collapsed.expandNode(b), rows);
      expect(collapsed.toggleNode(b), rows);
      // The intermediate directory's own state is not consulted.
      final intermediate = tree.flatten(
        expansion: ExpansionState.withCollapsed([b]),
        compactFolders: true,
      );
      expect(identical(intermediate.expandNode(b), intermediate), isTrue);
      expect(
        intermediate.collapseNode(b).expansion,
        ExpansionState.withCollapsed([b, c]),
      );
    });

    test('a hidden chain member acts on the deepest directory too', () {
      final chained = DirectoryTree.fromPaths([
        '/r/lib/src/utils/a.dart',
        '/r/README.md',
      ], options: fixedR);
      NodeId at(String path) => chained.idOf(path)!;
      final root = at('/r');
      final lib = at('/r/lib');
      final src = at('/r/lib/src');
      final utils = at('/r/lib/src/utils');
      final rows = chained.flatten(
        expansion: const ExpansionState.collapsed(),
        compactFolders: true,
      );
      expect(table(rows), ['r|0|-CLM|']);
      // The order of the two updates does not matter.
      final visibleFirst = rows.toggleNode(root).expandNode(src);
      final hiddenFirst = rows.expandNode(src).toggleNode(root);
      const expected = [
        'r|0|ECLM|',
        'lib/src/utils|1|EC-M|0',
        'a.dart|2|--LM|01',
        'README.md|1|--LM|0',
      ];
      expect(table(visibleFirst), expected);
      expect(table(hiddenFirst), expected);
      expect(hiddenFirst.expansion, ExpansionState.withExpanded([root, utils]));
      expect(hiddenFirst.requestedExpansion, hiddenFirst.expansion);
      // While hidden, every chain member acts on utils, and the rows stay.
      final expanded = rows.expandNode(lib);
      expect(expanded.expansion, ExpansionState.withExpanded([utils]));
      expectAllRowsReused(rows, expanded, 'expandNode(lib)');
      expect(rows.toggleNode(src).expansion, expanded.expansion);
      expect(identical(expanded.expandNode(src), expanded), isTrue);
      expect(expanded.toggleNode(lib).expansion, rows.expansion);
      expect(expanded.collapseNode(src).expansion, rows.expansion);
      // An intermediate directory's own state is never written.
      final own = rows.withExpansion(ExpansionState.withExpanded([src]));
      expect(identical(own.collapseNode(src).expansion, own.expansion), true);
    });

    test('revealed matches can be collapsed and expanded again', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
      );
      final collapsed = rows.collapseNode(b);
      expect(table(collapsed), [
        'r|0|ECL-|',
        'a|1|EC--|0',
        'x.txt|2|---M|01',
        'y.txt|2|--LM|01',
        'b|1|-C--|0',
        'top.txt|1|--LM|0',
      ]);
      expect(collapsed.expandNode(b), rows);
    });

    test('updates keep the tree, filter, and compactFolders', () {
      final rows = tree.flatten(filter: textFiles, compactFolders: true);
      final next = rows.toggleNode(a);
      expect(identical(next.tree, tree), isTrue);
      expect(next.filter, same(textFiles));
      expect(next.compactFolders, isTrue);
    });
  });

  group('withExpansion', () {
    test('recomputes the rows for a new state without revealing', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
      );
      final reset = rows.withExpansion(const ExpansionState.collapsed());
      expect(table(reset), ['r|0|-CL-|']);
      expect(reset.expansion, const ExpansionState.collapsed());
      expect(reset.filter, same(textFiles));
      final all = reset.withExpansion(
        const ExpansionState.collapsed().expandSubtree(tree, r),
      );
      expect(all, rows);
    });

    test('returns the same rows for an equal state', () {
      final rows = tree.flatten(expansion: ExpansionState.withExpanded([r, a]));
      expect(
        identical(
          rows.withExpansion(ExpansionState.withExpanded([a, r])),
          rows,
        ),
        isTrue,
      );
    });

    test('equals a full flatten without revealing', () {
      for (var seed = 0; seed < 30; seed++) {
        final random = Random(seed);
        final tree = randomTree(random);
        final filter = random.nextBool() ? randomFilter(random, tree) : null;
        final compactFolders = random.nextBool();
        final rows = tree.flatten(
          filter: filter,
          compactFolders: compactFolders,
        );
        final state = randomExpansion(random, tree);
        expect(
          rows.withExpansion(state),
          tree.flatten(
            expansion: state,
            filter: filter,
            expandMatches: false,
            compactFolders: compactFolders,
          ),
          reason: 'seed $seed',
        );
      }
    });
  });

  group('hidden roots', () {
    // Two roots that both have directories, so sibling relations cross the
    // root boundary.
    final twoRoots = DirectoryTree.fromPaths([
      '/m/',
      '/m/d1/f1.txt',
      '/m/d2/f2.txt',
      '/n/',
      '/n/e1/g1.txt',
    ]);
    const d2 = NodeId('/m/d2');

    test('isLast and guides cross the root boundary', () {
      expect(table(twoRoots.flatten()), [
        'm|0|EC-M|',
        'd1|1|EC-M|1',
        'f1.txt|2|--LM|11',
        'd2|1|ECLM|1',
        'f2.txt|2|--LM|10',
        'n|0|ECLM|',
        'e1|1|ECLM|0',
        'g1.txt|2|--LM|00',
      ]);
      expect(table(twoRoots.flatten(showRoots: false)), [
        'd1|0|EC-M|',
        'f1.txt|1|--LM|1',
        'd2|0|EC-M|',
        'f2.txt|1|--LM|1',
        'e1|0|ECLM|',
        'g1.txt|1|--LM|0',
      ]);
    });

    test('updates splice across the root boundary and reuse rows', () {
      final rows = twoRoots.flatten(showRoots: false);
      final collapsed = rows.collapseNode(d2);
      expect(table(collapsed), [
        'd1|0|EC-M|',
        'f1.txt|1|--LM|1',
        'd2|0|-C-M|',
        'e1|0|ECLM|',
        'g1.txt|1|--LM|0',
      ]);
      expect(identical(collapsed[0], rows[0]), isTrue);
      expect(identical(collapsed[1], rows[1]), isTrue);
      expect(identical(collapsed[3], rows[4]), isTrue);
      expect(identical(collapsed[4], rows[5]), isTrue);
      expect(collapsed.expandNode(d2), rows);
      expect(collapsed.showRoots, isFalse);
    });

    test('keyboard helpers at depth 0', () {
      final rows = tree.flatten(showRoots: false);
      expect(rows.map((row) => row.label), [
        'q.md',
        'a',
        'x.txt',
        'y.txt',
        'b',
        'c',
        'z.txt',
        'top.txt',
      ]);
      expect(
        [for (var i = 0; i < rows.length; i++) rows.parentIndexOf(i)],
        [null, null, 1, 1, null, 4, 5, null],
      );
      expect(
        [for (var i = 0; i < rows.length; i++) rows.firstChildIndexOf(i)],
        [null, 2, null, null, 5, 6, null, null],
      );
    });

    test('root ids have no row', () {
      final rows = tree.flatten(showRoots: false, compactFolders: true);
      for (final root in tree.roots) {
        expect(rows.indexOfNode(root), -1, reason: '$root');
        expect(rows.rowOf(root), isNull, reason: '$root');
      }
      expect(rows.indexOfNode(q), 0);
      expect(rows.indexOfNode(b), rows.indexOfNode(c));
      expect(rows.indexOfNode(top), rows.length - 1);
    });

    test('updates of root ids are no-ops, whatever their state', () {
      for (final expansion in [
        const ExpansionState.expanded(),
        const ExpansionState.collapsed(),
        ExpansionState.withCollapsed([r, other]),
      ]) {
        final rows = tree.flatten(expansion: expansion, showRoots: false);
        for (final root in [r, other]) {
          expect(identical(rows.expandNode(root), rows), isTrue);
          expect(identical(rows.collapseNode(root), rows), isTrue);
          expect(identical(rows.toggleNode(root), rows), isTrue);
        }
      }
      // With the roots shown, the same ids toggle as usual.
      final shown = tree.flatten();
      expect(identical(shown.toggleNode(r), shown), isFalse);
    });

    test('withExpansion and updates keep showRoots', () {
      final rows = tree.flatten(
        filter: textFiles,
        compactFolders: true,
        showRoots: false,
      );
      expect(rows.toggleNode(a).showRoots, isFalse);
      expect(rows.collapseNode(c).expandNode(c).showRoots, isFalse);
      final reset = rows.withExpansion(const ExpansionState.collapsed());
      expect(reset.showRoots, isFalse);
      expect(
        reset,
        tree.flatten(
          expansion: const ExpansionState.collapsed(),
          filter: textFiles,
          expandMatches: false,
          compactFolders: true,
          showRoots: false,
        ),
      );
      expect(table(reset), ['a|0|-C--|', 'b/c|0|-C--|', 'top.txt|0|--LM|']);
    });

    test('updates never call the filter again', () {
      var calls = 0;
      final counting = TreeFilter.where<Object?>((node) {
        calls++;
        return node.name.endsWith('.txt');
      });
      var rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: counting,
        compactFolders: true,
        showRoots: false,
      );
      expect(calls, tree.length);
      for (final id in [r, other, a, b, c, q, top, unknown, a, r, c]) {
        rows = rows.toggleNode(id).expandNode(id).collapseNode(id);
      }
      rows = rows.withExpansion(const ExpansionState.expanded());
      expect(rows, isNotEmpty);
      expect(calls, tree.length);
    });
  });

  group('requested expansion', () {
    test('equals the effective state when nothing is revealed', () {
      final plain = tree.flatten();
      expect(identical(plain.requestedExpansion, plain.expansion), isTrue);
      final toggled = plain.toggleNode(a).reveal(z).collapseNode(c);
      expect(identical(toggled.requestedExpansion, toggled.expansion), isTrue);
      final unrevealed = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
        expandMatches: false,
      );
      expect(unrevealed.requestedExpansion, const ExpansionState.collapsed());
      expect(
        identical(unrevealed.requestedExpansion, unrevealed.expansion),
        isTrue,
      );
      // The expanded default already shows every match.
      final searched = tree.flatten(filter: textFiles);
      expect(identical(searched.requestedExpansion, searched.expansion), true);
    });

    test('stays one object when the reveal would only touch states that '
        'are never consulted', () {
      // A hidden root counts as expanded whatever the state says.
      final hiddenRoot = DirectoryTree.fromPaths([
        '/r/lib/a.dart',
        '/r/b.txt',
      ], options: fixedR);
      final rows = hiddenRoot.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: TreeFilter.where<Object?>((node) => node.name == 'b.txt'),
        showRoots: false,
      );
      expect(table(rows), ['b.txt|0|--LM|']);
      expect(rows.expansion, const ExpansionState.collapsed());
      expect(identical(rows.requestedExpansion, rows.expansion), isTrue);
      // A directory that continues a compacted chain is never consulted:
      // the row a/b expands as b.
      final chain = DirectoryTree.fromPaths([
        '/r/a/b/x.txt',
        '/r/a/b/y.txt',
        '/r/q.txt',
      ], options: fixedR);
      final opened = ExpansionState.withExpanded([
        chain.idOf('/r')!,
        chain.idOf('/r/a/b')!,
      ]);
      final chained = chain.flatten(
        expansion: opened,
        filter: TreeFilter.where<Object?>((node) => node.name == 'x.txt'),
        compactFolders: true,
      );
      expect(table(chained), ['r|0|ECL-|', 'a/b|1|ECL-|0', 'x.txt|2|--LM|00']);
      expect(identical(chained.expansion, opened), isTrue);
      expect(identical(chained.requestedExpansion, opened), isTrue);
      // withExpansion with revealMatches agrees.
      expect(
        identical(
          rows.withExpansion(
            const ExpansionState.collapsed(),
            revealMatches: true,
          ),
          rows,
        ),
        isTrue,
      );
    });

    test('a search reveals folders only in the effective state', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
      );
      expect(rows.expansion, ExpansionState.withExpanded([r, a, b, c]));
      expect(rows.requestedExpansion, const ExpansionState.collapsed());
      // Collapsing a revealed folder: both states end collapsed.
      final collapsed = rows.collapseNode(b);
      expect(collapsed.expansion, ExpansionState.withExpanded([r, a, c]));
      expect(
        identical(collapsed.requestedExpansion, rows.requestedExpansion),
        isTrue,
      );
      // Expanding a revealed folder: the rows stay, the choice is recorded.
      final expanded = rows.expandNode(a);
      expect(identical(expanded, rows), isFalse);
      expect(identical(expanded.expansion, rows.expansion), isTrue);
      expect(expanded.requestedExpansion, ExpansionState.withExpanded([a]));
      for (var i = 0; i < rows.length; i++) {
        expect(identical(expanded[i], rows[i]), isTrue);
      }
      // Expanding it again changes nothing at all.
      expect(identical(expanded.expandNode(a), expanded), isTrue);
      // toggleNode decides from what the rows show: a is open, so it closes
      // in both states.
      final toggled = expanded.toggleNode(a);
      expect(toggled.expansion, ExpansionState.withExpanded([r, b, c]));
      expect(toggled.requestedExpansion, const ExpansionState.collapsed());
    });

    test('an id inside a compacted row maps to the row node in both', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
        compactFolders: true,
      );
      expect(describe(rows.rowOf(b)!), 'b/c|1|EC--|0');
      // The search reveals c, the row's node, but not b, whose state the
      // row b/c never consults.
      expect(rows.expansion, ExpansionState.withExpanded([r, a, c]));
      final expanded = rows.expandNode(b);
      expect(expanded.requestedExpansion, ExpansionState.withExpanded([c]));
      final collapsed = rows.collapseNode(b);
      expect(collapsed.expansion, ExpansionState.withExpanded([r, a]));
      expect(collapsed.requestedExpansion, const ExpansionState.collapsed());
    });

    test('withExpansion re-applies the reveals only when asked', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
      );
      // Without revealMatches, a collapsed state shows only the roots.
      final plain = rows.withExpansion(const ExpansionState.collapsed());
      expect(table(plain), ['r|0|-CL-|']);
      expect(plain.expansion, const ExpansionState.collapsed());
      expect(plain.requestedExpansion, const ExpansionState.collapsed());
      // With revealMatches, the matches show again.
      final again = plain.withExpansion(
        const ExpansionState.collapsed(),
        revealMatches: true,
      );
      expect(again, rows);
      expect(again.expansion, rows.expansion);
      expect(again.requestedExpansion, const ExpansionState.collapsed());
      // Both states unchanged: the same rows.
      expect(
        identical(
          rows.withExpansion(
            const ExpansionState.collapsed(),
            revealMatches: true,
          ),
          rows,
        ),
        isTrue,
      );
      // Only the requested state changes: the rows are reused.
      final requestedOnly = rows.withExpansion(
        ExpansionState.withExpanded([a]),
        revealMatches: true,
      );
      expect(identical(requestedOnly, rows), isFalse);
      expect(requestedOnly.expansion, rows.expansion);
      expect(
        requestedOnly.requestedExpansion,
        ExpansionState.withExpanded([a]),
      );
      for (var i = 0; i < rows.length; i++) {
        expect(identical(requestedOnly[i], rows[i]), isTrue);
      }
      // revealMatches without a filter changes nothing.
      final unfiltered = tree.flatten(
        expansion: const ExpansionState.collapsed(),
      );
      final same = unfiltered.withExpansion(
        ExpansionState.withExpanded([r]),
        revealMatches: true,
      );
      expect(identical(same.expansion, same.requestedExpansion), isTrue);
      expect(table(same).first, 'other|0|-C-M|');
    });

    test('persisting requestedExpansion drops the search reveals', () {
      // The user had /r open, then searched for .txt files.
      final searched = tree.flatten(
        expansion: ExpansionState.withExpanded([r]),
        filter: textFiles,
      );
      expect(searched.expansion, ExpansionState.withExpanded([r, a, b, c]));
      // During the search: open a (already revealed), close b (revealed),
      // and open other (hidden by the search).
      final edited = searched.expandNode(a).collapseNode(b).expandNode(other);
      final json = edited.requestedExpansion.toJson();
      final restored = ExpansionState.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(restored, ExpansionState.withExpanded([r, a, other]));
      // The search is cleared: the user's choices survive, the folder only
      // the search opened (c) does not.
      final after = tree.flatten(expansion: restored);
      expect(table(after), [
        'other|0|EC-M|',
        'q.md|1|--LM|1',
        'r|0|ECLM|',
        'a|1|EC-M|0',
        'x.txt|2|---M|01',
        'y.txt|2|--LM|01',
        'b|1|-C-M|0',
        'top.txt|1|--LM|0',
      ]);
      expect(edited.expansion.isExpanded(c), isTrue);
      expect(restored.isExpanded(c), isFalse);
    });
  });

  group('reveal', () {
    test('expands the collapsed ancestors and reuses the other rows', () {
      final rows = tree.flatten(expansion: const ExpansionState.collapsed());
      final revealed = rows.reveal(z);
      expect(table(revealed), [
        'other|0|-C-M|',
        'r|0|ECLM|',
        'a|1|-C-M|0',
        'b|1|EC-M|0',
        'c|2|ECLM|01',
        'z.txt|3|--LM|010',
        'top.txt|1|--LM|0',
      ]);
      expect(revealed.expansion, ExpansionState.withExpanded([r, b, c]));
      expect(revealed.requestedExpansion, revealed.expansion);
      expect(identical(revealed[0], rows[0]), isTrue);
      expect(identical(revealed[1], rows[1]), isFalse);
      expect(revealed.indexOfNode(z), 5);
    });

    test('reveals a directory without expanding it', () {
      final rows = tree.flatten(expansion: const ExpansionState.collapsed());
      final revealed = rows.reveal(c);
      expect(revealed.rowOf(c)!.isExpanded, isFalse);
      expect(revealed.expansion, ExpansionState.withExpanded([r, b]));
    });

    test('only expands what is still collapsed', () {
      final rows = tree.flatten(expansion: ExpansionState.withExpanded([r, c]));
      final revealed = rows.reveal(z);
      expect(revealed.expansion, ExpansionState.withExpanded([r, b, c]));
    });

    test('returns the same rows when nothing needs to change', () {
      final rows = tree.flatten(expansion: const ExpansionState.collapsed());
      expect(identical(rows.reveal(r), rows), isTrue);
      expect(identical(rows.reveal(unknown), rows), isTrue);
      final searched = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
      );
      // q.md does not match and has no matching descendant.
      expect(identical(searched.reveal(q), searched), isTrue);
      expect(identical(searched.reveal(other), searched), isTrue);
      // Already visible.
      expect(identical(searched.reveal(z), searched), isTrue);
      final hidden = tree.flatten(showRoots: false);
      expect(identical(hidden.reveal(r), hidden), isTrue);
    });

    test('never expands hidden roots', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        showRoots: false,
      );
      final revealed = rows.reveal(z);
      expect(revealed.expansion, ExpansionState.withExpanded([b, c]));
      expect(table(revealed), [
        'q.md|0|---M|',
        'a|0|-C-M|',
        'b|0|EC-M|',
        'c|1|ECLM|1',
        'z.txt|2|--LM|10',
        'top.txt|0|--LM|',
      ]);
    });

    test('a node inside a visible compacted row is already visible', () {
      final chain = DirectoryTree.fromPaths([
        '/p/',
        '/p/a/b/c/x.txt',
        '/p/a/b/c/y.txt',
        '/p/a/b/c/d/z.txt',
      ]);
      NodeId at(String path) => chain.idOf(path)!;
      final rows = chain.flatten(
        expansion: const ExpansionState.collapsed(),
        compactFolders: true,
      );
      expect(table(rows), ['p/a/b/c|0|-CLM|']);
      // Revealing a chain member changes nothing...
      expect(identical(rows.reveal(at('/p/a/b')), rows), isTrue);
      expect(identical(rows.reveal(at('/p/a/b/c')), rows), isTrue);
      // ...while expanding an ancestor of it one by one would open the row,
      // because a chain member acts on the chain's node.
      expect(rows.expandNode(at('/p/a')).rowOf(at('/p/a/b'))!.isExpanded, true);
      // A node below the row: only the rows' own nodes are expanded, never
      // the chain members p, a, and b.
      final deep = rows.reveal(at('/p/a/b/c/d/z.txt'));
      expect(
        deep.expansion,
        ExpansionState.withExpanded([at('/p/a/b/c'), at('/p/a/b/c/d')]),
      );
      expect(table(deep), [
        'p/a/b/c|0|ECLM|',
        'd|1|EC-M|0',
        'z.txt|2|--LM|01',
        'x.txt|1|---M|0',
        'y.txt|1|--LM|0',
      ]);
      final file = rows.reveal(at('/p/a/b/c/x.txt'));
      expect(file.expansion, ExpansionState.withExpanded([at('/p/a/b/c')]));
      expect(file.rowOf(at('/p/a/b/c/d'))!.isExpanded, isFalse);
    });

    test('a chain member the filter hides is revealed through its chain', () {
      final chain = DirectoryTree.fromPaths([
        '/r/p/x/b/c.txt',
        '/r/q.txt',
      ], options: fixedR);
      NodeId at(String path) => chain.idOf(path)!;
      final b = at('/r/p/x/b');
      final rows = chain.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: TreeFilter.where<Object?>((node) => node.name == 'x'),
        expandMatches: false,
        compactFolders: true,
      );
      expect(table(rows), ['r|0|-CL-|']);
      expect(rows.indexOfNode(b), -1);
      // b does not pass the filter, but the row p/x/b shows it once /r is
      // open, so revealing b opens /r, as revealing the match x does.
      final revealed = rows.reveal(b);
      expect(identical(revealed, rows), isFalse);
      expect(table(revealed), ['r|0|ECL-|', 'p/x/b|1|--LM|0']);
      expect(revealed.expansion, ExpansionState.withExpanded([at('/r')]));
      expect(revealed.requestedExpansion, revealed.expansion);
      expect(revealed.indexOfNode(b), 1);
      expect(rows.reveal(at('/r/p/x')), revealed);
      expect(identical(revealed.reveal(b), revealed), isTrue);
      // The file below the chain stays hidden: no row can show it.
      expect(identical(rows.reveal(at('/r/p/x/b/c.txt')), rows), isTrue);
    });

    test('applies to both states during a search', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: textFiles,
      );
      // Collapse the revealed /r, then reveal z.txt again.
      final closed = rows.collapseNode(r);
      expect(table(closed), ['r|0|-CL-|']);
      final revealed = closed.reveal(z);
      expect(revealed.expansion, ExpansionState.withExpanded([r, a, b, c]));
      expect(
        revealed.requestedExpansion,
        ExpansionState.withExpanded([r, b, c]),
      );
      expect(revealed.indexOfNode(z), greaterThan(0));
    });
  });

  group('the filter is never called again', () {
    test('after flatten, no update calls the filter', () {
      var calls = 0;
      final counting = TreeFilter.where<Object?>((node) {
        calls++;
        return node.name.endsWith('.txt');
      });
      var rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: counting,
        compactFolders: true,
      );
      expect(calls, tree.length);
      for (final id in [r, a, b, c, other, q, top, unknown, a, r, r, c, z]) {
        rows = rows
            .toggleNode(id)
            .expandNode(id)
            .collapseNode(id)
            .collapseNode(r)
            .reveal(id);
      }
      rows = rows
          .withExpansion(const ExpansionState.expanded())
          .withExpansion(const ExpansionState.collapsed(), revealMatches: true)
          .withExpansion(const ExpansionState.collapsed());
      var checksum = 0;
      for (final row in rows) {
        checksum += row.isMatch ? 1 : 0;
        checksum += row.hasChildren ? 1 : 0;
        checksum += row.guides.length;
      }
      expect(checksum, greaterThanOrEqualTo(0));
      expect(calls, tree.length);
    });

    test('on random trees and random updates', () {
      for (var seed = 0; seed < 20; seed++) {
        final random = Random(1000 + seed);
        final tree = randomTree(random);
        var calls = 0;
        final counting = TreeFilter.where<Object?>((node) {
          calls++;
          return node.name.contains('a');
        });
        for (final showRoots in const [true, false]) {
          for (final compactFolders in const [false, true]) {
            calls = 0;
            var rows = tree.flatten(
              expansion: randomExpansion(random, tree),
              filter: counting,
              expandMatches: random.nextBool(),
              compactFolders: compactFolders,
              showRoots: showRoots,
            );
            expect(calls, tree.length, reason: 'seed $seed');
            for (var step = 0; step < 40; step++) {
              final id = pickId(random, tree, rows);
              rows = switch (random.nextInt(6)) {
                0 => rows.expandNode(id),
                1 => rows.collapseNode(id),
                2 => rows.toggleNode(id),
                3 => rows.reveal(id),
                4 => rows.withExpansion(randomExpansion(random, tree)),
                _ => rows.withExpansion(
                  randomExpansion(random, tree),
                  revealMatches: true,
                ),
              };
              expect(rows.indexOfNode(id), greaterThanOrEqualTo(-1));
            }
            expect(calls, tree.length, reason: 'seed $seed');
          }
        }
      }
    });
  });

  group('incremental updates equal a full flatten', () {
    for (var seed = 0; seed < 60; seed++) {
      test('random tree $seed', () {
        final random = Random(seed);
        final tree = randomTree(random);
        for (final showRoots in const [true, false]) {
          for (final compactFolders in const [false, true]) {
            for (final filtered in const [false, true]) {
              final filter = filtered ? randomFilter(random, tree) : null;
              final initial = randomExpansion(random, tree);
              final expandMatches = random.nextBool();
              var rows = tree.flatten(
                expansion: initial,
                filter: filter,
                expandMatches: expandMatches,
                compactFolders: compactFolders,
                showRoots: showRoots,
              );
              expect(rows.requestedExpansion, initial);
              if (filter == null ||
                  !expandMatches ||
                  matchesVisible(
                    tree.flatten(
                      expansion: initial,
                      filter: filter,
                      expandMatches: false,
                      compactFolders: compactFolders,
                      showRoots: showRoots,
                    ),
                  )) {
                // Nothing to reveal: the two states are one object.
                expect(
                  identical(rows.requestedExpansion, rows.expansion),
                  true,
                );
              }
              // The requested state, modeled without any reveal.
              var requested = initial;
              for (var step = 0; step < 30; step++) {
                final id = pickId(random, tree, rows);
                final operation = random.nextInt(9) ~/ 2;
                final reason =
                    'seed $seed, showRoots $showRoots, compact '
                    '$compactFolders, filter $filtered, step $step, '
                    '${operationNames[operation]} $id';
                final TreeRows<int> next;
                if (operation == 4) {
                  final state = randomExpansion(random, tree);
                  final revealMatches = random.nextBool();
                  next = rows.withExpansion(
                    state,
                    revealMatches: revealMatches,
                  );
                  requested = state;
                  final full = tree.flatten(
                    expansion: state,
                    filter: filter,
                    expandMatches: revealMatches,
                    compactFolders: compactFolders,
                    showRoots: showRoots,
                  );
                  expectSameRows(next, full, reason);
                  if (state == rows.requestedExpansion &&
                      full.expansion == rows.expansion) {
                    expect(identical(next, rows), isTrue, reason: reason);
                  }
                } else {
                  next = switch (operation) {
                    0 => rows.expandNode(id),
                    1 => rows.collapseNode(id),
                    2 => rows.toggleNode(id),
                    _ => rows.reveal(id),
                  };
                  final change = expectedChange(rows, id, operation);
                  if (change != null) {
                    requested = applyChange(requested, change);
                  }
                  expectUpdate(rows, next, id, operation, reason);
                  final full = tree.flatten(
                    expansion: next.expansion,
                    filter: filter,
                    expandMatches: false,
                    compactFolders: compactFolders,
                    showRoots: showRoots,
                  );
                  expectSameRows(next, full, reason);
                }
                expect(next.requestedExpansion, requested, reason: reason);
                expectLookups(next, reason);
                rows = next;
              }
            }
          }
        }
      });
    }

    test('the random operations cover every kind of update', () {
      final seen = <String>{};
      for (var seed = 0; seed < 60; seed++) {
        final random = Random(seed);
        final tree = randomTree(random);
        for (final showRoots in const [true, false]) {
          for (final compactFolders in const [false, true]) {
            for (final filtered in const [false, true]) {
              final filter = filtered ? randomFilter(random, tree) : null;
              var rows = tree.flatten(
                expansion: randomExpansion(random, tree),
                filter: filter,
                expandMatches: random.nextBool(),
                compactFolders: compactFolders,
                showRoots: showRoots,
              );
              for (var step = 0; step < 30; step++) {
                final id = pickId(random, tree, rows);
                final operation = random.nextInt(4);
                final next = switch (operation) {
                  0 => rows.expandNode(id),
                  1 => rows.collapseNode(id),
                  2 => rows.toggleNode(id),
                  _ => rows.reveal(id),
                };
                seen.addAll(
                  classify(rows, next, id, operation, filtered: filtered),
                );
                rows = next;
              }
            }
          }
        }
      }
      expect(
        seen,
        containsAll(<String>[
          'unknown',
          'file',
          'unchanged',
          'hidden directory',
          'hidden by filter',
          'inserted several rows',
          'removed several rows',
          'chain member',
          'chain member with filter',
          'several top-level rows',
          'hidden root',
          'hidden root with filter',
          'depth-0 rows from several roots',
          'update with hidden roots',
          'chain member under hidden roots',
          'requested state only',
          'reveal',
          'reveal under hidden roots',
          'reveal with compact folders',
          'reveal of a visible node',
          'reveal of a chain member',
          'reveal of a filtered node',
          'reveal of a filtered chain member',
          'reveal of a hidden root',
          'hidden chain member',
          'hidden chain member with filter',
        ]),
      );
    });
  });
}

/// Names of the operations the property test picks, by number.
const operationNames = [
  'expand',
  'collapse',
  'toggle',
  'reveal',
  'withExpansion',
];

/// What an update should change, computed from [before] and the tree API
/// alone: the ids whose state becomes `expanded` in both expansion states,
/// or `null` when the update must return [before] unchanged.
///
/// [operation] is 0 (expandNode), 1 (collapseNode), 2 (toggleNode), or 3
/// (reveal).
({List<NodeId> ids, bool expanded})? expectedChange(
  TreeRows<Object?> before,
  NodeId id,
  int operation,
) {
  final tree = before.tree;
  final node = tree[id];
  if (node == null || (node.isRoot && !before.showRoots)) return null;
  if (operation == 3) {
    if (before.indexOfNode(id) >= 0) return null;
    // A compacted chain shows when its first node passes the filter, even
    // where a deeper member does not.
    if (!passesFilter(before.filter, tree, chainHead(before, node))) {
      return null;
    }
    return (
      ids: [
        for (final ancestor in tree.ancestorsOf(id))
          if (!(ancestor.isRoot && !before.showRoots) &&
              !continuesChain(before, ancestor))
            ancestor.id,
      ],
      expanded: true,
    );
  }
  if (node.isFile) return null;
  // Visible or not, an id acts on the deepest directory of its chain.
  final target = chainEnd(before, node).id;
  final index = before.indexOfNode(id);
  if (index >= 0 && before[index].id != target) {
    throw StateError('the row of $id does not show $target');
  }
  final wanted = switch (operation) {
    0 => true,
    1 => false,
    _ => !before.expansion.isExpanded(target),
  };
  return (ids: [target], expanded: wanted);
}

/// Whether [node] can be visible under [filter]: it or a descendant
/// matches.
bool passesFilter(
  TreeFilter? filter,
  DirectoryTree<Object?> tree,
  TreeNode<Object?> node,
) =>
    filter == null ||
    filter.matches(node) ||
    tree.descendantsOf(node.id).any(filter.matches);

/// Whether [node] shares its compacted row with its only child, so its own
/// state is never consulted.
bool continuesChain(TreeRows<Object?> rows, TreeNode<Object?> node) {
  if (!rows.compactFolders ||
      node is! DirectoryNode<Object?> ||
      node.children.length != 1) {
    return false;
  }
  return rows.tree[node.children.single]!.isDirectory;
}

/// The deepest directory of the compacted chain that [node] belongs to:
/// [node] unless it continues a chain.
TreeNode<Object?> chainEnd(TreeRows<Object?> rows, TreeNode<Object?> node) {
  var end = node;
  while (continuesChain(rows, end)) {
    end = rows.tree.childrenOf(end.id).single;
  }
  return end;
}

/// The first node of the compacted chain that [node] belongs to: the node
/// the row that shows [node] starts with. Chains never include a hidden
/// root.
TreeNode<Object?> chainHead(TreeRows<Object?> rows, TreeNode<Object?> node) {
  var head = node;
  for (;;) {
    final parent = rows.tree.parentOf(head.id);
    if (parent == null ||
        (parent.isRoot && !rows.showRoots) ||
        !continuesChain(rows, parent)) {
      return head;
    }
    head = parent;
  }
}

ExpansionState applyChange(
  ExpansionState state,
  ({List<NodeId> ids, bool expanded}) change,
) => change.expanded
    ? state.expandAll(change.ids)
    : state.collapseAll(change.ids);

/// Checks what an update did against the contract: how both expansion
/// states changed, and that every row outside the changed block is reused.
void expectUpdate(
  TreeRows<Object?> before,
  TreeRows<Object?> after,
  NodeId id,
  int operation,
  String reason,
) {
  expect(identical(after.tree, before.tree), isTrue, reason: reason);
  expect(after.filter, same(before.filter), reason: reason);
  expect(after.compactFolders, before.compactFolders, reason: reason);
  expect(after.showRoots, before.showRoots, reason: reason);
  final change = expectedChange(before, id, operation);
  if (change == null) {
    expect(identical(after, before), isTrue, reason: reason);
    return;
  }
  final effective = applyChange(before.expansion, change);
  final requested = applyChange(before.requestedExpansion, change);
  expect(after.expansion, effective, reason: reason);
  expect(after.requestedExpansion, requested, reason: reason);
  if (operation == 3) {
    expect(after.indexOfNode(id), greaterThanOrEqualTo(0), reason: reason);
  }
  if (effective == before.expansion) {
    // The rows do not change.
    if (requested == before.requestedExpansion) {
      expect(identical(after, before), isTrue, reason: reason);
    } else {
      expectAllRowsReused(before, after, reason);
    }
    return;
  }
  // The row whose state changed: the id's row (an id inside a compacted row
  // finds that row), or for reveal the topmost collapsed deciding ancestor.
  var index = before.indexOfNode(id);
  if (operation == 3) {
    NodeId? topmost;
    for (final ancestor in change.ids) {
      if (!before.expansion.isExpanded(ancestor)) topmost = ancestor;
    }
    index = before.indexOfNode(topmost!);
    expect(index, greaterThanOrEqualTo(0), reason: reason);
  }
  if (index < 0) {
    expectAllRowsReused(before, after, reason);
    return;
  }
  final problems = <String>[];
  final oldEnd = blockEnd(before, index);
  final newEnd = blockEnd(after, index);
  for (var i = 0; i < index; i++) {
    if (!identical(after[i], before[i])) problems.add('row $i before block');
  }
  if (after.length - newEnd != before.length - oldEnd) {
    problems.add('tail length changed');
  } else {
    for (var k = 0; k < before.length - oldEnd; k++) {
      if (!identical(after[newEnd + k], before[oldEnd + k])) {
        problems.add('row ${oldEnd + k} after block');
      }
    }
  }
  if (identical(after[index], before[index])) problems.add('row not replaced');
  if (after[index].isExpanded != change.expanded) problems.add('row state');
  if (after[index].id != before[index].id) problems.add('row id');
  if (change.expanded ? oldEnd != index + 1 : newEnd != index + 1) {
    problems.add('block shape');
  }
  expect(problems, isEmpty, reason: reason);
}

/// Checks that [after] has exactly the row objects of [before].
void expectAllRowsReused(
  TreeRows<Object?> before,
  TreeRows<Object?> after,
  String reason,
) {
  final problems = <String>[];
  if (after.length != before.length) problems.add('length changed');
  for (var i = 0; i < before.length && i < after.length; i++) {
    if (!identical(after[i], before[i])) problems.add('row $i replaced');
  }
  expect(problems, isEmpty, reason: reason);
}

/// One past the last row of the block that starts at [index]: the row and
/// its descendant rows.
int blockEnd(List<TreeRow<Object?>> rows, int index) {
  final depth = rows[index].depth;
  var end = index + 1;
  while (end < rows.length && rows[end].depth > depth) {
    end++;
  }
  return end;
}

void expectSameRows(
  TreeRows<Object?> actual,
  TreeRows<Object?> expected,
  String reason,
) {
  expect(actual.expansion, expected.expansion, reason: reason);
  expect(actual.length, expected.length, reason: reason);
  for (var i = 0; i < expected.length; i++) {
    if (actual[i] != expected[i]) {
      fail('$reason: row $i is ${actual[i]}, flatten gives ${expected[i]}');
    }
  }
}

/// Checks indexOfNode, parentIndexOf, and firstChildIndexOf against a
/// brute-force reading of the rows.
void expectLookups(TreeRows<Object?> rows, String reason) {
  final problems = <String>[];
  final positions = <NodeId, int>{};
  for (var i = 0; i < rows.length; i++) {
    for (final member in rows[i].chain) {
      positions[member.id] = i;
    }
  }
  for (final node in rows.tree.nodes) {
    final expected = positions[node.id] ?? -1;
    if (rows.indexOfNode(node.id) != expected) {
      problems.add('indexOfNode(${node.id})');
    }
  }
  if (rows.indexOfNode(const NodeId('/no/such/node')) != -1) {
    problems.add('unknown id');
  }
  final lastAtDepth = <int>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final depth = row.depth;
    final parent = depth == 0 ? null : lastAtDepth[depth - 1];
    if (depth < lastAtDepth.length) {
      lastAtDepth[depth] = i;
    } else {
      lastAtDepth.add(i);
    }
    if (rows.parentIndexOf(i) != parent) problems.add('parentIndexOf($i)');
    final head = row.chain.first;
    if (parent != null) {
      if (head.parent != rows[parent].id) problems.add('parent of $i');
    } else if (rows.showRoots) {
      if (!head.isRoot) problems.add('depth-0 row $i is not a root');
    } else {
      // Hidden roots: a depth-0 row is a child of a top-level node.
      final parentNode = head.parent == null ? null : rows.tree[head.parent!];
      if (parentNode == null || !parentNode.isRoot) {
        problems.add('depth-0 row $i is not a child of a root');
      }
    }
    if (!rows.showRoots && row.chain.any((member) => member.isRoot)) {
      problems.add('row $i shows a hidden root');
    }
    final next = i + 1;
    final child = next < rows.length && rows[next].depth == depth + 1
        ? next
        : null;
    if (rows.firstChildIndexOf(i) != child) {
      problems.add('firstChildIndexOf($i)');
    }
    if ((child != null) != (row.isExpanded && row.hasChildren)) {
      problems.add('children shown for $i');
    }
    if (!identical(row.node, row.chain.last)) problems.add('node of $i');
  }
  expect(problems, isEmpty, reason: reason);
}

/// Whether every match of the filter of [rows] that can have a row (all
/// but hidden roots) is visible, so revealing the matches changes nothing.
bool matchesVisible(TreeRows<Object?> rows) {
  final filter = rows.filter;
  if (filter == null) return true;
  for (final node in rows.tree.nodes) {
    if (!filter.matches(node)) continue;
    if (node.isRoot && !rows.showRoots) continue;
    if (rows.indexOfNode(node.id) < 0) return false;
  }
  return true;
}

/// The kinds of update that [before] -> [after] exercised.
Set<String> classify(
  TreeRows<Object?> before,
  TreeRows<Object?> after,
  NodeId id,
  int operation, {
  required bool filtered,
}) {
  final kinds = <String>{};
  final node = before.tree[id];
  final depthZero = before.where((row) => row.depth == 0).toList();
  if (depthZero.length > 1) kinds.add('several top-level rows');
  if (!before.showRoots &&
      depthZero.map((row) => row.chain.first.parent).toSet().length > 1) {
    kinds.add('depth-0 rows from several roots');
  }
  if (operation == 3) return kinds..addAll(classifyReveal(before, after, id));
  if (node == null) return kinds..add('unknown');
  if (node.isFile) return kinds..add('file');
  if (node.isRoot && !before.showRoots) {
    return kinds..add(filtered ? 'hidden root with filter' : 'hidden root');
  }
  if (identical(after, before)) return kinds..add('unchanged');
  if (after.expansion == before.expansion) {
    return kinds..add('requested state only');
  }
  if (!before.showRoots) kinds.add('update with hidden roots');
  final index = before.indexOfNode(id);
  if (index < 0 && continuesChain(before, node)) {
    kinds.add(
      filtered ? 'hidden chain member with filter' : 'hidden chain member',
    );
  }
  if (index < 0) {
    final ancestorsExpanded = before.tree
        .ancestorsOf(id)
        .every((ancestor) => before.expansion.isExpanded(ancestor.id));
    kinds.add(
      filtered && ancestorsExpanded ? 'hidden by filter' : 'hidden directory',
    );
    return kinds;
  }
  if (before[index].id != id) {
    kinds.add(filtered ? 'chain member with filter' : 'chain member');
    if (!before.showRoots) kinds.add('chain member under hidden roots');
  }
  final delta = after.length - before.length;
  if (delta > 1) kinds.add('inserted several rows');
  if (delta < -1) kinds.add('removed several rows');
  return kinds;
}

/// The kinds of reveal that [before] -> [after] exercised.
Set<String> classifyReveal(
  TreeRows<Object?> before,
  TreeRows<Object?> after,
  NodeId id,
) {
  final node = before.tree[id];
  if (node == null) return {'reveal of an unknown id'};
  if (node.isRoot && !before.showRoots) return {'reveal of a hidden root'};
  final index = before.indexOfNode(id);
  if (index >= 0) {
    return {
      'reveal of a visible node',
      if (before[index].id != id) 'reveal of a chain member',
    };
  }
  if (identical(after, before)) return {'reveal of a filtered node'};
  return {
    'reveal',
    if (!passesFilter(before.filter, before.tree, node))
      'reveal of a filtered chain member',
    if (!before.showRoots) 'reveal under hidden roots',
    if (before.compactFolders) 'reveal with compact folders',
  };
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

/// An id to update: usually a directory (visible or hidden), sometimes a
/// visible row's node, an intermediate directory of a compacted row, a
/// top-level node, a file, or an unknown id.
NodeId pickId(
  Random random,
  DirectoryTree<Object?> tree,
  TreeRows<Object?> rows,
) {
  final directories = tree.directories.toList();
  final files = tree.files.toList();
  final roll = random.nextInt(20);
  if (roll == 0 || tree.isEmpty) return const NodeId('/not/in/tree');
  if (roll == 1) return tree.roots[random.nextInt(tree.roots.length)];
  if (roll < 4 && files.isNotEmpty) {
    return files[random.nextInt(files.length)].id;
  }
  if (roll < 6 && rows.compactFolders) {
    // A directory that continues a chain, whether or not its row shows.
    final members = [
      for (final directory in directories)
        if (continuesChain(rows, directory)) directory,
    ];
    if (members.isNotEmpty) {
      return members[random.nextInt(members.length)].id;
    }
  }
  if (roll < 8 && rows.isNotEmpty) {
    final chained = [
      for (final row in rows)
        if (row.chain.length > 1) row,
    ];
    if (chained.isNotEmpty) {
      final row = chained[random.nextInt(chained.length)];
      return row.chain[random.nextInt(row.chain.length - 1)].id;
    }
  }
  if (roll < 11 && rows.isNotEmpty) {
    return rows[random.nextInt(rows.length)].id;
  }
  if (directories.isEmpty) return tree.nodes.first.id;
  return directories[random.nextInt(directories.length)].id;
}
