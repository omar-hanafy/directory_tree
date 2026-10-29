import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

List<NodeId> _ids(List<String> values) => [for (final v in values) NodeId(v)];

void main() {
  group('TreeDiff.compute', () {
    test('a tree compared with itself or an equal rebuild is empty', () {
      final tree = DirectoryTree.fromPaths(['/r/a.txt', '/r/lib/x.dart']);
      expect(TreeDiff.compute(tree, tree).isEmpty, isTrue);
      final rebuilt = DirectoryTree.fromPaths(['/r/lib/x.dart', '/r/a.txt']);
      expect(TreeDiff.compute(tree, rebuilt).isEmpty, isTrue);
    });

    test('two empty trees give an empty diff', () {
      final diff = TreeDiff.compute(
        DirectoryTree<int>.empty(),
        DirectoryTree<int>.empty(),
      );
      expect(diff.isEmpty, isTrue);
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
      expect(diff.changed, isEmpty);
    });

    test('from and to an empty tree', () {
      final tree = DirectoryTree.fromPaths(['/r/a.txt', '/r/d/b.txt']);
      final empty = DirectoryTree<Never>.empty();
      final all = _ids(['/r', '/r/d', '/r/d/b.txt', '/r/a.txt']);
      expect(tree.nodes.map((n) => n.id), all, reason: 'pre-order');
      expect(TreeDiff.compute(empty, tree).added, all);
      expect(TreeDiff.compute(tree, empty).removed, all);
    });

    test('added and removed files and directories in pre-order', () {
      final before = DirectoryTree.fromPaths(['/r/a.txt', '/r/lib/x.dart']);
      final after = DirectoryTree.fromPaths([
        '/r/b.txt',
        '/r/a.txt',
        '/r/src/y.dart',
      ]);
      final diff = TreeDiff.compute(before, after);
      expect(diff.added, _ids(['/r/src', '/r/src/y.dart', '/r/b.txt']));
      expect(diff.removed, _ids(['/r/lib', '/r/lib/x.dart']));
      expect(diff.changed, isEmpty);
      expect(diff.isEmpty, isFalse);
    });

    test('a data change marks the node changed', () {
      final before = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a.txt', data: 1),
        TreeEntry.file('/r/b.txt', data: 1),
      ]);
      final after = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a.txt', data: 1),
        TreeEntry.file('/r/b.txt', data: 2),
      ]);
      final diff = TreeDiff.compute(before, after);
      expect(diff.changed, _ids(['/r/b.txt']));
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
    });

    test('a kind change marks the node changed', () {
      final before = DirectoryTree.fromPaths(['/r/x', '/r/y']);
      final after = DirectoryTree.fromPaths(['/r/x/', '/r/y']);
      expect(TreeDiff.compute(before, after).changed, _ids(['/r/x']));
    });

    test('an explicit directory becoming inferred marks it changed', () {
      final before = DirectoryTree.fromPaths(['/r/', '/r/lib/', '/r/lib/a']);
      final after = DirectoryTree.fromPaths(['/r/', '/r/lib/a']);
      expect(TreeDiff.compute(before, after).changed, _ids(['/r/lib']));
    });

    test('a node becoming top level or nested is a change', () {
      final before = DirectoryTree.fromPaths(['/a/b/c.txt']);
      final after = DirectoryTree.fromPaths(['/a/b/c.txt', '/a/d.txt']);
      expect(before.roots, _ids(['/a/b']));
      expect(after.roots, _ids(['/a']));
      final diff = TreeDiff.compute(before, after);
      expect(diff.added, _ids(['/a', '/a/d.txt']));
      expect(diff.removed, isEmpty);
      // c.txt kept its parent; only its depth shifted, which is not a change.
      expect(diff.changed, _ids(['/a/b']));

      final back = TreeDiff.compute(after, before);
      expect(back.removed, _ids(['/a', '/a/d.txt']));
      expect(back.changed, _ids(['/a/b']));
    });

    test('a root strategy change is reported through parents', () {
      const paths = ['/x/a/1.txt', '/x/b/2.txt', '/x/b/c/3.txt'];
      final minimal = DirectoryTree.fromPaths(paths);
      final common = DirectoryTree.fromPaths(
        paths,
        options: const TreeOptions(roots: TreeRoots.commonAncestor()),
      );
      expect(minimal.roots, _ids(['/x/a', '/x/b']));
      expect(common.roots, _ids(['/x']));
      final diff = TreeDiff.compute(minimal, common);
      expect(diff.added, _ids(['/x']));
      expect(diff.changed, _ids(['/x/a', '/x/b']));
    });

    test('a top-level label change marks the node changed', () {
      final before = DirectoryTree.fromPaths(['/a/src/x', '/b/other/y']);
      final after = DirectoryTree.fromPaths(['/a/src/x', '/b/src/y']);
      expect(before[NodeId('/a/src')]!.label, 'src');
      expect(after[NodeId('/a/src')]!.label, 'a/src');
      final diff = TreeDiff.compute(before, after);
      expect(diff.changed, _ids(['/a/src']));
      expect(diff.added, _ids(['/b/src', '/b/src/y']));
      expect(diff.removed, _ids(['/b/other', '/b/other/y']));
    });

    test('a case-insensitive spelling change is a change, not add/remove', () {
      const options = TreeOptions(paths: PathPolicy.caseInsensitive);
      final before = DirectoryTree.fromPaths([
        '/Repo/A.txt',
        '/Repo/b.txt',
      ], options: options);
      final after = DirectoryTree.fromPaths([
        '/Repo/a.txt',
        '/Repo/b.txt',
      ], options: options);
      final diff = TreeDiff.compute(before, after);
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
      expect(diff.changed, _ids(['/repo/a.txt']));

      final renamedRoot = DirectoryTree.fromPaths([
        '/repo/a.txt',
        '/repo/b.txt',
      ], options: options);
      expect(
        TreeDiff.compute(after, renamedRoot).changed,
        _ids(['/repo', '/repo/a.txt', '/repo/b.txt']),
      );
    });

    test('trees with different type arguments compare entries by value', () {
      final ints = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a'),
        TreeEntry.file('/r/b', data: 1),
      ]);
      final strings = DirectoryTree<String>.build(const [
        TreeEntry.file('/r/a'),
        TreeEntry.file('/r/b', data: '1'),
      ]);
      final diff = TreeDiff.compute(ints, strings);
      expect(diff.changed, _ids(['/r/b']));
      expect(diff.added, isEmpty);
      expect(
        TreeDiff.compute(
          ints,
          DirectoryTree.fromPaths(['/r/a', '/r/b']),
        ).changed,
        _ids(['/r/b']),
      );
      expect(
        TreeDiff.compute(
          DirectoryTree<int>.build(const [TreeEntry.file('/r/a')]),
          DirectoryTree.fromPaths(['/r/a']),
        ).isEmpty,
        isTrue,
      );
    });

    test('sibling order and typed comparators are ignored', () {
      final sizeFirst = TreeOptions(
        order: TreeOrder.by<int>(
          (a, b) => (b.data ?? 0).compareTo(a.data ?? 0),
        ),
      );
      const entries = [
        TreeEntry<int>.file('/r/a', data: 1),
        TreeEntry<int>.file('/r/b', data: 2),
        TreeEntry<int>.file('/r/c/d', data: 3),
      ];
      final bySize = DirectoryTree<int>.build(entries, options: sizeFirst);
      final byName = DirectoryTree<int>.build(entries);
      expect(
        bySize.nodes.map((n) => n.id),
        isNot(byName.nodes.map((n) => n.id)),
      );
      expect(TreeDiff.compute(bySize, byName).isEmpty, isTrue);
      expect(TreeDiff.compute(byName, bySize).isEmpty, isTrue);
    });

    test('a 1000-level chain diffs without recursion', () {
      final deep = [for (var i = 0; i < 1000; i++) 'd$i'].join('/');
      final before = DirectoryTree.fromPaths(['/$deep/a.txt']);
      final after = DirectoryTree.fromPaths(['/$deep/b.txt']);
      final diff = TreeDiff.compute(before, after);
      expect(diff.added, _ids(['/$deep/b.txt']));
      expect(diff.removed, _ids(['/$deep/a.txt']));
    });

    test('matches set arithmetic on random trees', () {
      final random = Random(42);
      String randomPath() {
        final depth = 1 + random.nextInt(4);
        return '/${[for (var i = 0; i < depth; i++) 'n${random.nextInt(4)}'].join('/')}';
      }

      for (var round = 0; round < 200; round++) {
        final before = DirectoryTree<int>.build([
          for (var i = 0; i < random.nextInt(40); i++)
            TreeEntry.file(randomPath(), data: random.nextInt(2)),
        ]);
        final after = DirectoryTree<int>.build([
          for (var i = 0; i < random.nextInt(40); i++)
            TreeEntry.file(randomPath(), data: random.nextInt(2)),
        ]);
        final diff = TreeDiff.compute(before, after);
        final beforeIds = [for (final n in before.nodes) n.id];
        final afterIds = [for (final n in after.nodes) n.id];
        expect(diff.added, [
          for (final id in afterIds)
            if (!before.contains(id)) id,
        ]);
        expect(diff.removed, [
          for (final id in beforeIds)
            if (!after.contains(id)) id,
        ]);
        expect(diff.changed, [
          for (final node in after.nodes)
            if (before[node.id] case final old?)
              if (old.kind != node.kind ||
                  old.path != node.path ||
                  old.label != node.label ||
                  old.entry != node.entry ||
                  old.parent != node.parent)
                node.id,
        ]);
      }
    });
  });

  group('TreeDiff value semantics', () {
    test('equal diffs are == with equal hashCode', () {
      final a = TreeDiff.compute(
        DirectoryTree.fromPaths(['/r/a']),
        DirectoryTree.fromPaths(['/r/b']),
      );
      final b = TreeDiff.compute(
        DirectoryTree<int>.build(const [TreeEntry.file('/r/a', data: 1)]),
        DirectoryTree<int>.build(const [TreeEntry.file('/r/b', data: 1)]),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final other = TreeDiff.compute(
        DirectoryTree<Never>.empty(),
        DirectoryTree.fromPaths(['/r/a']),
      );
      expect(a, isNot(other));
    });

    test('lists are unmodifiable', () {
      final diff = TreeDiff.compute(
        DirectoryTree.fromPaths(['/r/a']),
        DirectoryTree.fromPaths(['/r/b']),
      );
      expect(() => diff.added.add(NodeId('x')), throwsUnsupportedError);
      expect(() => diff.removed.add(NodeId('x')), throwsUnsupportedError);
      expect(() => diff.changed.add(NodeId('x')), throwsUnsupportedError);
    });

    test('toString lists the ids', () {
      final diff = TreeDiff.compute(
        DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a'),
          TreeEntry.file('/r/c', data: 1),
        ]),
        DirectoryTree<int>.build(const [
          TreeEntry.file('/r/b'),
          TreeEntry.file('/r/c', data: 2),
        ]),
      );
      expect(
        diff.toString(),
        'TreeDiff(added: [/r/b], removed: [/r/a], changed: [/r/c])',
      );
    });
  });
}
