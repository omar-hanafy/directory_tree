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

NodeId id(DirectoryTree<Object?> tree, String path) => tree.idOf(path)!;

void main() {
  group('pre-order layout', () {
    final tree = sampleTree();

    test('nodes are in pre-order with roots and children ordered', () {
      expect(tree.nodes.map((node) => node.path.toString()), [
        '/other',
        '/other/q.md',
        '/r',
        '/r/a',
        '/r/a/x.txt',
        '/r/a/y.txt',
        '/r/b',
        '/r/b/c',
        '/r/b/c/z.txt',
        '/r/top.txt',
      ]);
      expect(tree.nodes.map((node) => node.depth), [
        0,
        1,
        0,
        1,
        2,
        2,
        1,
        2,
        3,
        1,
      ]);
    });

    test('roots, counts, and node kinds', () {
      expect(tree.roots, [id(tree, '/other'), id(tree, '/r')]);
      expect(tree.rootNodes.map((node) => node.name), ['other', 'r']);
      expect(tree.length, 10);
      expect(tree.isEmpty, isFalse);
      expect(tree.isNotEmpty, isTrue);
      expect(tree.fileCount, 5);
      expect(tree.directoryCount, 5);
      expect(tree.files.map((node) => node.name), [
        'q.md',
        'x.txt',
        'y.txt',
        'z.txt',
        'top.txt',
      ]);
      expect(tree.directories.map((node) => node.name), [
        'other',
        'r',
        'a',
        'b',
        'c',
      ]);
    });

    test('indexOf and subtreeSizeOf', () {
      final expected = <String, (int, int)>{
        '/other': (0, 2),
        '/other/q.md': (1, 1),
        '/r': (2, 8),
        '/r/a': (3, 3),
        '/r/a/x.txt': (4, 1),
        '/r/a/y.txt': (5, 1),
        '/r/b': (6, 3),
        '/r/b/c': (7, 2),
        '/r/b/c/z.txt': (8, 1),
        '/r/top.txt': (9, 1),
      };
      expected.forEach((path, value) {
        final (index, size) = value;
        expect(tree.indexOf(id(tree, path)), index, reason: path);
        expect(tree.subtreeSizeOf(id(tree, path)), size, reason: path);
        expect(tree.nodes[index].path.toString(), path);
      });
    });

    test('childrenOf, parentOf, and DirectoryNode.children agree', () {
      expect(tree.childrenOf(id(tree, '/r')).map((node) => node.name), [
        'a',
        'b',
        'top.txt',
      ]);
      expect(tree.childrenOf(id(tree, '/r/b')).map((node) => node.name), ['c']);
      expect(tree.childrenOf(id(tree, '/r/a/x.txt')), isEmpty);
      final r = tree.nodeAt('/r')! as DirectoryNode<int>;
      expect(r.children, tree.childrenOf(r.id).map((node) => node.id));
      expect(r.hasChildren, isTrue);
      expect(tree.parentOf(id(tree, '/r/b/c'))!.path.toString(), '/r/b');
      expect(tree.parentOf(id(tree, '/r')), isNull);
    });

    test('ancestorsOf is nearest first and excludes the node', () {
      expect(
        tree
            .ancestorsOf(id(tree, '/r/b/c/z.txt'))
            .map((node) => node.path.toString()),
        ['/r/b/c', '/r/b', '/r'],
      );
      expect(tree.ancestorsOf(id(tree, '/r')), isEmpty);
    });

    test('descendantsOf is the pre-order slice after the node', () {
      expect(tree.descendantsOf(id(tree, '/r/b')).map((node) => node.name), [
        'c',
        'z.txt',
      ]);
      expect(tree.descendantsOf(id(tree, '/r')), hasLength(7));
      expect(tree.descendantsOf(id(tree, '/r/top.txt')), isEmpty);
      final index = tree.indexOf(id(tree, '/r'));
      expect(
        tree.descendantsOf(id(tree, '/r')),
        tree.nodes.sublist(index + 1, index + 8),
      );
    });

    test('isAncestor is strict', () {
      expect(tree.isAncestor(id(tree, '/r'), id(tree, '/r/b/c/z.txt')), true);
      expect(tree.isAncestor(id(tree, '/r/b'), id(tree, '/r/b/c')), true);
      expect(tree.isAncestor(id(tree, '/r/b'), id(tree, '/r/b')), false);
      expect(tree.isAncestor(id(tree, '/r/b/c'), id(tree, '/r/b')), false);
      expect(tree.isAncestor(id(tree, '/r/a'), id(tree, '/r/b/c')), false);
      expect(
        tree.isAncestor(id(tree, '/other'), id(tree, '/r/top.txt')),
        false,
      );
    });

    test('rootOf finds the top-level ancestor or the node itself', () {
      expect(tree.rootOf(id(tree, '/r/b/c/z.txt'))!.path.toString(), '/r');
      expect(tree.rootOf(id(tree, '/r'))!.path.toString(), '/r');
      expect(tree.rootOf(id(tree, '/other/q.md'))!.path.toString(), '/other');
      expect(tree.rootOf(id(tree, '/r/top.txt'))!.path.toString(), '/r');
    });

    test('operator [], contains, idOf, and nodeAt', () {
      final z = id(tree, '/r/b/c/z.txt');
      expect(tree[z]!.name, 'z.txt');
      expect(tree.contains(z), isTrue);
      expect(tree.idOf(r'\r\b\c\z.txt'), z);
      expect(tree.nodeAt('/r//b/./c/z.txt')!.id, z);
      expect(tree.idOf('/not/here'), isNotNull);
      expect(tree.nodeAt('/not/here'), isNull);
      expect(tree.idOf(''), isNull);
      expect(tree.nodeAt('../escape'), isNull);
    });
  });

  group('nodes', () {
    final tree = sampleTree();

    test('expose identity, position, entry, and kind', () {
      final z = tree.nodeAt('/r/b/c/z.txt')!;
      expect(z, isA<FileNode<int>>());
      expect(z.id, const NodeId('/r/b/c/z.txt'));
      expect(z.path, TreePath.parse('/r/b/c/z.txt'));
      expect(z.name, 'z.txt');
      expect(z.label, 'z.txt');
      expect(z.parent, id(tree, '/r/b/c'));
      expect(z.depth, 3);
      expect(z.entry, const TreeEntry<int>.file('/r/b/c/z.txt', data: 4));
      expect(z.data, 4);
      expect(z.isExplicit, isTrue);
      expect(z.kind, TreeNodeKind.file);
      expect(z.isFile, isTrue);
      expect(z.isDirectory, isFalse);
      expect(z.isRoot, isFalse);

      final c = tree.nodeAt('/r/b/c')!;
      expect(c, isA<DirectoryNode<int>>());
      expect(c.isExplicit, isFalse);
      expect(c.entry, isNull);
      expect(c.data, isNull);

      final b = tree.nodeAt('/r/b')!;
      expect(b.isExplicit, isTrue);
      expect(b.data, 3);

      final r = tree.nodeAt('/r')!;
      expect(r.isRoot, isTrue);
      expect(r.parent, isNull);
      expect(r.depth, 0);
    });

    test('a switch over a node is exhaustive', () {
      String describe(TreeNode<int> node) => switch (node) {
        FileNode<int>() => 'file',
        DirectoryNode<int>(:final children) => 'dir(${children.length})',
      };
      expect(tree.nodes.map(describe).toList(), [
        'dir(1)',
        'file',
        'dir(3)',
        'dir(2)',
        'file',
        'file',
        'dir(1)',
        'dir(1)',
        'file',
        'file',
      ]);
    });

    test('have value equality and a consistent hashCode', () {
      final other = sampleTree();
      for (var i = 0; i < tree.length; i++) {
        expect(other.nodes[i], tree.nodes[i]);
        expect(other.nodes[i].hashCode, tree.nodes[i].hashCode);
        expect(identical(other.nodes[i], tree.nodes[i]), isFalse);
      }
      final changed = DirectoryTree<int>.build([
        const TreeEntry.file('/r/a/x.txt', data: 99),
        ...tree.entries.skip(1),
      ]);
      expect(changed.nodeAt('/r/a/x.txt'), isNot(tree.nodeAt('/r/a/x.txt')));
      expect(changed.nodeAt('/r/a'), tree.nodeAt('/r/a'));
    });

    test('toString names the path', () {
      expect(tree.nodeAt('/r/a/x.txt').toString(), 'FileNode(/r/a/x.txt)');
      expect(tree.nodeAt('/r').toString(), 'DirectoryNode(/r, children: 3)');
    });

    test('children lists are unmodifiable', () {
      final r = tree.nodeAt('/r')! as DirectoryNode<int>;
      expect(() => r.children.add(const NodeId('x')), throwsUnsupportedError);
    });
  });

  group('unknown ids never throw', () {
    final tree = sampleTree();
    const unknown = NodeId('/does/not/exist');

    test('lookups return null, -1, 0, false, or empty', () {
      expect(tree[unknown], isNull);
      expect(tree.contains(unknown), isFalse);
      expect(tree.indexOf(unknown), -1);
      expect(tree.subtreeSizeOf(unknown), 0);
      expect(tree.childrenOf(unknown), isEmpty);
      expect(tree.parentOf(unknown), isNull);
      expect(tree.rootOf(unknown), isNull);
      expect(tree.ancestorsOf(unknown), isEmpty);
      expect(tree.descendantsOf(unknown), isEmpty);
      expect(tree.isAncestor(unknown, tree.roots.first), isFalse);
      expect(tree.isAncestor(tree.roots.first, unknown), isFalse);
    });

    test('empty trees answer every lookup', () {
      final empty = DirectoryTree<int>.empty();
      expect(empty.nodes, isEmpty);
      expect(empty.roots, isEmpty);
      expect(empty[unknown], isNull);
      expect(empty.rootOf(unknown), isNull);
      expect(empty.childrenOf(unknown), isEmpty);
      expect(empty.isEmpty, isTrue);
    });
  });

  group('collections are unmodifiable', () {
    final tree = sampleTree();

    test('nodes, roots, rootNodes, entries, issues, childrenOf', () {
      expect(() => tree.nodes.removeLast(), throwsUnsupportedError);
      expect(() => tree.roots.clear(), throwsUnsupportedError);
      expect(() => tree.rootNodes.clear(), throwsUnsupportedError);
      expect(() => tree.entries.clear(), throwsUnsupportedError);
      expect(() => tree.issues.clear(), throwsUnsupportedError);
      expect(
        () => tree.childrenOf(tree.roots.last).clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('constructors', () {
    test('fromPaths makes directories from trailing separators', () {
      final tree = DirectoryTree.fromPaths([
        '/p/file.txt',
        '/p/empty/',
        r'/p/win\',
      ]);
      expect(tree, isA<DirectoryTree<Never>>());
      expect(tree.nodeAt('/p/file.txt')!.isFile, isTrue);
      expect(tree.nodeAt('/p/empty')!.isDirectory, isTrue);
      expect(tree.nodeAt('/p/empty')!.isExplicit, isTrue);
      expect(tree.nodeAt('/p/win')!.isDirectory, isTrue);
    });

    test('fromPaths respects a policy where backslash is not a separator', () {
      final tree = DirectoryTree.fromPaths(
        [r'/p/name\', '/p/dir/'],
        options: const TreeOptions(
          paths: PathPolicy(backslashIsSeparator: false),
        ),
      );
      expect(tree.nodeAt(r'/p/name\')!.isFile, isTrue);
      expect(tree.nodeAt('/p/dir')!.isDirectory, isTrue);
    });

    test('empty keeps fixed roots, which exist even without entries', () {
      final tree = DirectoryTree<int>.empty(
        options: const TreeOptions(roots: TreeRoots.fixed(['/a', '/b'])),
      );
      expect(tree.rootNodes.map((node) => node.path.toString()), ['/a', '/b']);
      expect(tree.entries, isEmpty);
      expect(DirectoryTree<int>.empty(), DirectoryTree<int>.build(const []));
    });
  });

  group('equality', () {
    test('trees built from the same entries in any order are equal', () {
      final a = sampleTree();
      final b = DirectoryTree<int>.build(a.entries.reversed);
      expect(b, a);
      expect(b.hashCode, a.hashCode);
      expect(b.nodes, a.nodes);
    });

    test('different options or data make trees unequal', () {
      final a = sampleTree();
      final insensitive = DirectoryTree<int>.build(
        a.entries,
        options: const TreeOptions(paths: PathPolicy.caseInsensitive),
      );
      expect(insensitive, isNot(a));
      final otherData = DirectoryTree<int>.build([
        for (final entry in a.entries)
          entry.isFile
              ? TreeEntry<int>.file(entry.path, data: (entry.data ?? 0) + 1)
              : entry,
      ]);
      expect(otherData, isNot(a));
    });

    test('toString summarizes the tree', () {
      expect(
        sampleTree().toString(),
        'DirectoryTree(roots: 2, nodes: 10, files: 5, issues: 0)',
      );
    });
  });

  group('toBuilder and rebuild', () {
    test('toBuilder is seeded with the entries and options', () {
      final tree = sampleTree();
      final builder = tree.toBuilder();
      expect(builder.entries, tree.entries);
      expect(builder.options, tree.options);
      expect(builder.build(), tree);
    });

    test('rebuild applies changes and keeps ids stable', () {
      final tree = sampleTree();
      final next = tree.rebuild(
        (builder) => builder
          ..addFile('/r/a/w.txt', data: 7)
          ..remove('/r/b'),
      );
      expect(next.nodeAt('/r/b'), isNull);
      expect(next.nodeAt('/r/b/c/z.txt'), isNull);
      expect(next.nodeAt('/r/a/w.txt')!.data, 7);
      expect(next.nodeAt('/r/a/x.txt')!.id, tree.nodeAt('/r/a/x.txt')!.id);
      expect(tree.nodeAt('/r/b'), isNotNull, reason: 'original unchanged');
    });

    test('skipped entries are not carried into the builder', () {
      final tree = DirectoryTree<int>.build([
        const TreeEntry.file(''),
        const TreeEntry.file('/a/b'),
        const TreeEntry.file('/a/b/c'),
      ]);
      expect(tree.issues, hasLength(2));
      expect(tree.toBuilder().entries, [const TreeEntry<int>.file('/a/b/c')]);
    });
  });

  group('deep trees', () {
    // Each level is explicit so the minimal roots keep the whole chain.
    List<TreeEntry<int>> chain(int depth) => [
      for (var level = 1; level <= depth; level++)
        TreeEntry<int>.directory(
          '/${List<String>.generate(level, (i) => 'd$i').join('/')}',
        ),
      TreeEntry<int>.file(
        '/${List<String>.generate(depth, (i) => 'd$i').join('/')}/leaf.txt',
        data: depth,
      ),
    ];

    test('a 1000-deep chain builds, walks, and compares', () {
      const depth = 1000;
      final tree = DirectoryTree<int>.build(chain(depth));
      expect(tree.length, depth + 1);
      expect(tree.roots, hasLength(1));
      final leaf = tree.nodes.last;
      expect(leaf.depth, depth);
      expect(leaf.data, depth);
      expect(tree.ancestorsOf(leaf.id), hasLength(depth));
      expect(tree.descendantsOf(tree.roots.single), hasLength(depth));
      expect(tree.rootOf(leaf.id)!.id, tree.roots.single);
      expect(tree.isAncestor(tree.roots.single, leaf.id), isTrue);
      expect(tree.subtreeSizeOf(tree.roots.single), depth + 1);
      for (var i = 1; i < tree.length; i++) {
        expect(tree.nodes[i].parent, tree.nodes[i - 1].id);
      }

      final again = DirectoryTree<int>.build(chain(depth).reversed);
      expect(again, tree);
      expect(again.hashCode, tree.hashCode);
      final rebuilt = tree.rebuild((builder) => builder.addFile('/d0/x.txt'));
      expect(rebuilt.length, depth + 2);
    });

    test('a 1000-deep chain with filesystem roots infers every level', () {
      const depth = 1000;
      final path = '/${List<String>.generate(depth, (i) => 's$i').join('/')}';
      final tree = DirectoryTree.fromPaths([
        path,
      ], options: const TreeOptions(roots: TreeRoots.filesystem()));
      expect(tree.length, depth + 1);
      expect(tree.rootNodes.single.name, '/');
      expect(tree.nodes.last.depth, depth);
      expect(tree.nodes.where((node) => node.isExplicit), hasLength(1));
    });
  });
}
