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

  group('row list sizing', () {
    // flatten allocates its row list once at an upper bound when one is
    // cheap (an expanded state with few exceptions, or a filter), trims it
    // afterwards, and otherwise grows it. Every path must give the oracle's
    // rows.
    final wide = DirectoryTree.fromPaths([
      for (var i = 0; i < 80; i++) '/r/d$i/f$i.txt',
      '/r/x/y/z/w.txt',
      '/s/only/one.txt',
    ]);
    final directories = [for (final node in wide.directories) node.id];

    test('the tree has more directories than the exception limit', () {
      expect(directories.length, greaterThan(70));
    });

    final states = <String, ExpansionState>{
      'everything expanded': const ExpansionState.expanded(),
      'one small folder collapsed': ExpansionState.withCollapsed([
        wide.idOf('/r/d3')!,
      ]),
      'the largest folder collapsed': ExpansionState.withCollapsed([
        wide.idOf('/r')!,
      ]),
      'most of the tree collapsed': ExpansionState.withCollapsed([
        for (var i = 0; i < 60; i++) wide.idOf('/r/d$i')!,
        wide.idOf('/s')!,
      ]),
      'more than 64 exceptions': ExpansionState.withCollapsed(
        directories.skip(2).take(70),
      ),
      'unknown and file exceptions': ExpansionState.withCollapsed([
        const NodeId('/nowhere'),
        wide.idOf('/r/d1/f1.txt')!,
      ]),
      'collapsed by default': ExpansionState.withExpanded([
        wide.idOf('/r')!,
        wide.idOf('/r/x')!,
      ]),
    };
    states.forEach((name, expansion) {
      test(name, () {
        for (final showRoots in const [true, false]) {
          for (final compactFolders in const [false, true]) {
            for (final filter in [
              null,
              nameFilter((name) => name.startsWith('f1')),
            ]) {
              final rows = wide.flatten(
                expansion: expansion,
                filter: filter,
                expandMatches: false,
                compactFolders: compactFolders,
                showRoots: showRoots,
              );
              expectRows(
                rows,
                oracleFlatten(
                  wide,
                  expansion: expansion,
                  filter: filter,
                  expandMatches: false,
                  compactFolders: compactFolders,
                  showRoots: showRoots,
                ),
                '$name, showRoots $showRoots, compact $compactFolders, '
                'filter ${filter != null}',
              );
              // Every slot of the list is a row (no unfilled slot remains).
              expect(rows.every((row) => row.node.id.value.isNotEmpty), true);
            }
          }
        }
      });
    });
  });

  group('derived properties deep in the tree', () {
    test('hasChildren, isMatch, label, and chain at depth 999', () {
      final segments = [for (var i = 0; i < 1000; i++) 'd$i'];
      final deep = DirectoryTree.fromPaths([
        '/${segments.first}/',
        '/${segments.join('/')}/leaf.txt',
        '/${segments.join('/')}/other.md',
      ]);
      final rows = deep.flatten(
        filter: nameFilter((name) => name == 'leaf.txt' || name == 'd998'),
      );
      final leaf = rows.rowOf(deep.idOf('/${segments.join('/')}/leaf.txt')!)!;
      expect(leaf.depth, 1000);
      expect(leaf.isMatch, isTrue);
      expect(leaf.hasChildren, isFalse);
      expect(leaf.label, 'leaf.txt');
      expect(leaf.chain.single, same(leaf.node));
      final parent = rows[rows.parentIndexOf(rows.indexOf(leaf))!];
      expect(parent.label, 'd999');
      expect(parent.hasChildren, isTrue);
      expect(parent.isMatch, isFalse);
      final matchedAncestor = rows.rowOf(
        deep.idOf('/${segments.take(999).join('/')}')!,
      )!;
      expect(matchedAncestor.isMatch, isTrue);
      // other.md does not match, so leaf.txt is the only visible child.
      expect(leaf.isLast, isTrue);
      final compacted = deep.flatten(compactFolders: true);
      expect(compacted.first.label, segments.join('/'));
      expect(compacted.first.chain, hasLength(1000));
      expect(compacted[1].label, 'leaf.txt');
      expect(compacted[1].hasChildren, isFalse);
    });

    test('derived lists are equal on every read and unmodifiable', () {
      final rows = tree.flatten(compactFolders: true);
      for (final row in rows) {
        expect(row.guides, row.guides);
        expect(row.chain, row.chain);
        expect(row.label, row.label);
        expect(() => row.chain.add(row.node), throwsUnsupportedError);
        expect(() => row.guides.add(true), throwsUnsupportedError);
      }
    });
  });

  group('hidden roots', () {
    test('multiple roots: their children are one list of depth-0 rows', () {
      final rows = tree.flatten(showRoots: false);
      expect(rows.showRoots, isFalse);
      expect(table(rows), [
        'q.md|0|---M|',
        'a|0|EC-M|',
        'x.txt|1|---M|1',
        'y.txt|1|--LM|1',
        'b|0|EC-M|',
        'c|1|ECLM|1',
        'z.txt|2|--LM|10',
        'top.txt|0|--LM|',
      ]);
      expect(rows.where((row) => row.node.isRoot), isEmpty);
      expect(tree.flatten().showRoots, isTrue);
    });

    test('a single root', () {
      final repo = DirectoryTree.fromPaths([
        '/repo/lib/main.dart',
        '/repo/lib/src/tree.dart',
        '/repo/README.md',
      ]);
      expect(table(repo.flatten(showRoots: false)), [
        'lib|0|EC-M|',
        'src|1|EC-M|1',
        'tree.dart|2|--LM|11',
        'main.dart|1|--LM|1',
        'README.md|0|--LM|',
      ]);
      // The DirectoryTree.flatten documentation example.
      final contents = repo.flatten(
        expansion: const ExpansionState.collapsed(),
        showRoots: false,
      );
      expect(contents.map((row) => row.label), ['lib', 'README.md']);
    });

    test('roots count as expanded whatever the expansion says', () {
      expect(
        table(
          tree.flatten(
            expansion: const ExpansionState.collapsed(),
            showRoots: false,
          ),
        ),
        ['q.md|0|---M|', 'a|0|-C-M|', 'b|0|-C-M|', 'top.txt|0|--LM|'],
      );
      final rootsCollapsed = tree.flatten(
        expansion: ExpansionState.withCollapsed([id('/r'), id('/other')]),
        showRoots: false,
      );
      expect(table(rootsCollapsed), table(tree.flatten(showRoots: false)));
    });

    test('roots without visible children are skipped, wherever they are', () {
      final fixed = DirectoryTree<Never>.build(
        const [TreeEntry.file('/r/x.txt'), TreeEntry.file('/r/y.txt')],
        options: const TreeOptions(
          roots: TreeRoots.fixed(['/a-empty', '/r', '/z-empty']),
        ),
      );
      expect(fixed.rootNodes.map((node) => node.name), [
        'a-empty',
        'r',
        'z-empty',
      ]);
      expect(table(fixed.flatten(showRoots: false)), [
        'x.txt|0|---M|',
        'y.txt|0|--LM|',
      ]);
      final empty = DirectoryTree<Never>.empty(
        options: const TreeOptions(roots: TreeRoots.fixed(['/a', '/b'])),
      );
      expect(empty.flatten(), hasLength(2));
      expect(empty.flatten(showRoots: false), isEmpty);
    });

    test('compaction never merges a root with its child', () {
      final chain = DirectoryTree.fromPaths(['/p/', '/p/a/b/f.txt']);
      expect(table(chain.flatten(compactFolders: true)), [
        'p/a/b|0|ECLM|',
        'f.txt|1|--LM|0',
      ]);
      expect(table(chain.flatten(compactFolders: true, showRoots: false)), [
        'a/b|0|ECLM|',
        'f.txt|1|--LM|0',
      ]);
      expect(table(tree.flatten(compactFolders: true, showRoots: false)), [
        'q.md|0|---M|',
        'a|0|EC-M|',
        'x.txt|1|---M|1',
        'y.txt|1|--LM|1',
        'b/c|0|EC-M|',
        'z.txt|1|--LM|1',
        'top.txt|0|--LM|',
      ]);
      const filesystem = TreeOptions(roots: TreeRoots.filesystem());
      final posix = DirectoryTree.fromPaths([
        '/usr/lib/x.so',
        '/usr/lib/y.so',
      ], options: filesystem);
      expect(
        posix
            .flatten(compactFolders: true, showRoots: false)
            .map((row) => row.label),
        ['usr/lib', 'x.so', 'y.so'],
      );
    });

    test('a filter never shows a hidden root and still reveals', () {
      final rows = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: nameFilter((name) => name == 'z.txt' || name == 'q.md'),
        showRoots: false,
      );
      expect(table(rows), [
        'q.md|0|---M|',
        'b|0|ECL-|',
        'c|1|ECL-|0',
        'z.txt|2|--LM|00',
      ]);
      // Revealing adds the ancestors of the matches, but not the hidden
      // roots: they count as expanded whatever the state says.
      expect(
        rows.expansion,
        ExpansionState.withExpanded([id('/r/b'), id('/r/b/c')]),
      );
      // A root that only matches itself shows nothing once hidden.
      final rootOnly = nameFilter((name) => name == 'r');
      expect(table(tree.flatten(filter: rootOnly)), ['r|0|E-LM|']);
      expect(tree.flatten(filter: rootOnly, showRoots: false), isEmpty);
      // Without revealing, collapsed directories stay collapsed.
      final unrevealed = tree.flatten(
        expansion: const ExpansionState.collapsed(),
        filter: nameFilter((name) => name == 'z.txt'),
        expandMatches: false,
        showRoots: false,
      );
      expect(table(unrevealed), ['b|0|-CL-|']);
    });

    test('a 1000-deep chain under a hidden root', () {
      final segments = [for (var i = 0; i < 1000; i++) 'd$i'];
      final deep = DirectoryTree.fromPaths([
        '/${segments.first}/',
        '/${segments.join('/')}/leaf.txt',
      ]);
      final rows = deep.flatten(showRoots: false);
      expect(rows, hasLength(1000));
      expect(rows.first.label, 'd1');
      expect(rows.last.depth, 999);
      expect(rows.last.guides, hasLength(999));
      final compacted = deep.flatten(compactFolders: true, showRoots: false);
      expect(compacted.first.chain, hasLength(999));
      expect(compacted.first.label, segments.skip(1).join('/'));
    });
  });

  group('agrees with a definitional oracle', () {
    for (var seed = 0; seed < 150; seed++) {
      test('random tree $seed', () {
        final random = Random(seed);
        final tree = randomTree(random);
        for (final showRoots in const [true, false]) {
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
                showRoots: showRoots,
              );
              final expected = oracleFlatten(
                tree,
                expansion: expansion,
                filter: filter,
                expandMatches: expandMatches,
                compactFolders: compactFolders,
                showRoots: showRoots,
              );
              expect(rows.showRoots, showRoots);
              expectRows(
                rows,
                expected,
                'seed $seed, showRoots $showRoots, compact $compactFolders, '
                'filter $filtered, expandMatches $expandMatches',
              );
            }
          }
        }
      });
    }

    test('the random trees have several roots of different kinds', () {
      final labels = <String>{};
      var multiRoot = 0;
      var chainsBelowHiddenRoots = 0;
      for (var seed = 0; seed < 150; seed++) {
        final tree = randomTree(Random(seed));
        labels.addAll(tree.rootNodes.map((node) => node.label));
        if (tree.roots.length > 1) multiRoot++;
        final hidden = tree.flatten(compactFolders: true, showRoots: false);
        chainsBelowHiddenRoots += hidden
            .where((row) => row.chain.length > 1)
            .length;
      }
      expect(multiRoot, greaterThan(30));
      expect(labels, containsAll(<String>['/', 'C:', '//nas/share', '.']));
      expect(chainsBelowHiddenRoots, greaterThan(10));
    });
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
/// visibility by scanning descendants, revealing by expanding the ancestors
/// of each match whose state is consulted (not hidden roots, not directories
/// that continue a compacted chain), chains by [DirectoryTree.childrenOf].
/// With [showRoots] false the depth-0 candidates are the children of every
/// root, in root order, as one sibling list.
({List<ExpectedRow> rows, ExpansionState expansion}) oracleFlatten(
  DirectoryTree<Object?> tree, {
  required ExpansionState expansion,
  required TreeFilter? filter,
  required bool expandMatches,
  required bool compactFolders,
  bool showRoots = true,
}) {
  final active = filter == null || filter.matchesAll ? null : filter;
  bool matches(TreeNode<Object?> node) =>
      active == null || active.matches(node);
  bool visible(TreeNode<Object?> node) =>
      active == null ||
      matches(node) ||
      tree.descendantsOf(node.id).any(matches);
  // Whether the state of [node] is ever consulted: not for a hidden root
  // (it counts as expanded), and not for a directory whose only child is a
  // directory under compaction (the row expands as its deepest directory).
  bool consulted(TreeNode<Object?> node) {
    if (!showRoots && node.isRoot) return false;
    if (!compactFolders) return true;
    final children = tree.childrenOf(node.id);
    return children.length != 1 || !children.single.isDirectory;
  }

  var state = expansion;
  if (active != null && expandMatches) {
    for (final node in tree.nodes) {
      if (!matches(node)) continue;
      state = state.expandAll(
        tree.ancestorsOf(node.id).where(consulted).map((node) => node.id),
      );
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

  emit(
    showRoots
        ? tree.rootNodes
        : [for (final root in tree.rootNodes) ...tree.childrenOf(root.id)],
    0,
    const [],
  );
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
