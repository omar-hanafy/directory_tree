import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

int sign(int value) => value.sign;

int noPreference(TreeNode<Object?> a, TreeNode<Object?> b) => 0;

List<String> childNames(DirectoryTree<Object?> tree, String path) => [
  for (final node in tree.childrenOf(tree.idOf(path)!)) node.name,
];

void main() {
  group('TreeOrder.compareNames', () {
    // (a, b, expected sign of compareNames(a, b))
    const table = <(String, String, int)>[
      ('file2', 'file10', -1),
      ('file10', 'file2', 1),
      ('a', 'B', -1),
      ('B', 'a', 1),
      ('A', 'a', -1),
      ('a', 'a', 0),
      ('x01', 'x1', -1),
      ('x1', 'x01', 1),
      ('x1y', 'x01', 1),
      ('', 'a', -1),
      ('a', '', 1),
      ('a', 'a1', -1),
      ('1', 'a', -1),
      ('_', '1', 1),
      ('.env', 'app', -1),
      ('a-1', 'a.1', -1),
      ('2', '10', -1),
      ('002', '10', -1),
      ('010', '9', 1),
      ('Zeta.md', 'alpha.md', 1),
      ('n99999999999999999999', 'n100000000000000000000', -1),
      ('n9007199254740993', 'n9007199254740992', 1),
      ('éa', 'Éb', -1),
      ('Éa', 'éa', -1),
      ('img12.png', 'img012.png', 1),
      ('v1.10', 'v1.9', 1),
    ];

    for (final (a, b, expected) in table) {
      test('compares "$a" and "$b"', () {
        expect(sign(TreeOrder.compareNames(a, b)), expected);
        expect(sign(TreeOrder.compareNames(b, a)), -expected);
      });
    }

    test('is a total order over generated names', () {
      const alphabet = [
        'a',
        'A',
        'b',
        'B',
        '0',
        '1',
        '9',
        '00',
        '10',
        '2',
        '.',
        '-',
        '_',
        ' ',
        'é',
        'É',
        '\u{1F600}',
      ];
      final random = Random(42);
      final names = <String>{
        for (var i = 0; i < 400; i++)
          List<String>.generate(
            random.nextInt(6),
            (_) => alphabet[random.nextInt(alphabet.length)],
          ).join(),
      }.toList();

      for (final a in names) {
        expect(TreeOrder.compareNames(a, a), 0);
        for (final b in names) {
          final ab = TreeOrder.compareNames(a, b);
          expect(sign(ab), -sign(TreeOrder.compareNames(b, a)));
          expect(ab == 0, a == b);
        }
      }

      final sorted = [...names]..sort(TreeOrder.compareNames);
      for (var i = 0; i < sorted.length; i++) {
        for (var j = i + 1; j < sorted.length; j++) {
          expect(
            TreeOrder.compareNames(sorted[i], sorted[j]),
            lessThan(0),
            reason: '"${sorted[i]}" before "${sorted[j]}"',
          );
        }
      }
    });
  });

  group('built-in comparators', () {
    final tree = DirectoryTree.fromPaths([
      '/r/b.txt',
      '/r/a/x',
      '/r/C.txt',
      '/r/D/y',
      '/r/file10',
      '/r/file2',
    ]);

    test('directoriesFirst is the default', () {
      expect(const TreeOptions().order, TreeOrder.directoriesFirst);
      expect(childNames(tree, '/r'), [
        'a',
        'D',
        'b.txt',
        'C.txt',
        'file2',
        'file10',
      ]);
    });

    test('alphabetical interleaves files and directories', () {
      final alphabetical = tree.rebuild(
        (builder) => builder.options = builder.options.copyWith(
          order: TreeOrder.alphabetical,
        ),
      );
      expect(childNames(alphabetical, '/r'), [
        'a',
        'b.txt',
        'C.txt',
        'D',
        'file2',
        'file10',
      ]);
    });
  });

  group('TreeOrder.by', () {
    test('orders by typed data', () {
      final bySize = TreeOrder.by<int>(
        (a, b) => (a.data ?? 0).compareTo(b.data ?? 0),
      );
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/big', data: 30),
        TreeEntry.file('/r/small', data: 10),
        TreeEntry.file('/r/mid', data: 20),
      ], options: TreeOptions(order: bySize));
      expect(childNames(tree, '/r'), ['small', 'mid', 'big']);
      expect(tree.options.order, same(bySize));
    });

    test('throws a TypeError for nodes of another type', () {
      final byInt = TreeOrder.by<int>((a, b) => 0);
      expect(
        () => DirectoryTree<String>.build(const [
          TreeEntry.file('/r/a'),
          TreeEntry.file('/r/b'),
        ], options: TreeOptions(order: byInt)),
        throwsA(isA<TypeError>()),
      );
    });

    test('accepts trees whose data type is a subtype', () {
      final byNum = TreeOrder.by<num>((a, b) => 0);
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a', data: 1),
        TreeEntry.file('/r/b', data: 2),
      ], options: TreeOptions(order: byNum));
      expect(tree.fileCount, 2);
    });

    test('rejects data-less fromPaths trees for a typed comparator', () {
      // fromPaths builds DirectoryTree<Object?>, whose nodes are not
      // TreeNode<num>, so a typed comparator fails loudly instead of
      // silently comparing nodes without data.
      final byNum = TreeOrder.by<num>((a, b) => 0);
      expect(
        () => DirectoryTree.fromPaths([
          '/r/a',
          '/r/b',
        ], options: TreeOptions(order: byNum)),
        throwsA(isA<TypeError>()),
      );
    });

    test('each call returns a new function', () {
      int compare(TreeNode<int> a, TreeNode<int> b) => 0;
      expect(TreeOrder.by<int>(compare), isNot(TreeOrder.by<int>(compare)));
    });
  });

  group('tie-breaks', () {
    test('ties fall back to the node id', () {
      final entries = ['/r/b', '/r/a', '/r/c', '/r/B'];
      for (final order in [entries, entries.reversed.toList()]) {
        final tree = DirectoryTree.fromPaths(
          order,
          options: const TreeOptions(order: noPreference),
        );
        expect(childNames(tree, '/r'), ['B', 'a', 'b', 'c']);
      }
    });

    test('roots are ordered with the same comparator', () {
      int reverseNames(TreeNode<Object?> a, TreeNode<Object?> b) =>
          TreeOrder.compareNames(b.name, a.name);
      final tree = DirectoryTree.fromPaths([
        '/x/alpha/1',
        '/x/beta/2',
        '/y/gamma/3',
      ], options: TreeOptions(order: reverseNames));
      expect(tree.rootNodes.map((node) => node.name), [
        'gamma',
        'beta',
        'alpha',
      ]);
    });

    test('roots with equal names are ordered by id', () {
      final tree = DirectoryTree.fromPaths(['/b/src/1', '/a/src/2']);
      expect(tree.rootNodes.map((node) => node.path.toString()), [
        '/a/src',
        '/b/src',
      ]);
    });
  });

  group('TreeOptions', () {
    test('defaults', () {
      const options = TreeOptions();
      expect(options.paths, const PathPolicy());
      expect(options.roots, const TreeRoots.minimal());
      expect(options.order, TreeOrder.directoriesFirst);
    });

    test('== and hashCode compare all fields', () {
      expect(const TreeOptions(), const TreeOptions());
      expect(const TreeOptions().hashCode, const TreeOptions().hashCode);
      expect(
        const TreeOptions(),
        isNot(const TreeOptions(paths: PathPolicy.caseInsensitive)),
      );
      expect(
        const TreeOptions(),
        isNot(const TreeOptions(roots: TreeRoots.filesystem())),
      );
      expect(
        const TreeOptions(),
        isNot(const TreeOptions(order: TreeOrder.alphabetical)),
      );
    });

    test('copyWith replaces only the given fields', () {
      const options = TreeOptions(paths: PathPolicy.caseInsensitive);
      expect(options.copyWith(), options);
      final changed = options.copyWith(roots: const TreeRoots.commonAncestor());
      expect(changed.paths, PathPolicy.caseInsensitive);
      expect(changed.roots, const TreeRoots.commonAncestor());
      expect(changed.order, TreeOrder.directoriesFirst);
    });

    test('toString names the order', () {
      expect(
        const TreeOptions().toString(),
        'TreeOptions(paths: ${const PathPolicy()}, '
        'roots: TreeRoots.minimal(), order: directoriesFirst)',
      );
      expect(
        const TreeOptions(order: TreeOrder.alphabetical).toString(),
        endsWith('order: alphabetical)'),
      );
      expect(
        TreeOptions(order: TreeOrder.by<int>((a, b) => 0)).toString(),
        endsWith('order: custom)'),
      );
    });
  });
}
