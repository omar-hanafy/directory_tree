import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

const _roots = ['/home/u', '/srv/app', 'C:/work', '//nas/share', 'rel', '/'];
const _names = [
  'src',
  'lib',
  'test',
  'a',
  'b',
  'c',
  'docs',
  'img',
  'x1',
  'x2',
  'x10',
  'Readme',
  'main.dart',
  'util.dart',
  '.env',
  'data.json',
  '\u00e9t\u00e9',
  'z',
];

/// Generates [count] entries whose keys are unique under [policy].
///
/// Names repeat across levels, so some files are ancestors of other entries
/// (conflicts) and many directories are inferred. With [mixedCase], segments
/// are randomly uppercased so ancestors arrive in several spellings.
List<TreeEntry<int>> generateEntries(
  int seed,
  int count,
  PathPolicy policy, {
  bool mixedCase = false,
}) {
  final random = Random(seed);
  final seen = <NodeId>{};
  final entries = <TreeEntry<int>>[];
  while (entries.length < count) {
    final buffer = StringBuffer(_roots[random.nextInt(_roots.length)]);
    final depth = 1 + random.nextInt(7);
    for (var i = 0; i < depth; i++) {
      var name = _names[random.nextInt(_names.length)];
      if (mixedCase && random.nextInt(3) == 0) name = name.toUpperCase();
      if (!buffer.toString().endsWith('/')) buffer.write('/');
      buffer.write(name);
    }
    final path = buffer.toString();
    if (!seen.add(policy.idOf(policy.parse(path)))) continue;
    final data = entries.length;
    entries.add(
      random.nextInt(5) == 0
          ? TreeEntry<int>.directory(path, data: data)
          : TreeEntry<int>.file(path, data: data),
    );
  }
  return entries;
}

List<NodeId> ids(DirectoryTree<Object?> tree) => [
  for (final node in tree.nodes) node.id,
];

void expectDeterministic(
  List<TreeEntry<int>> entries,
  TreeOptions options, {
  required int shuffles,
}) {
  final baseline = DirectoryTree<int>.build(entries, options: options);
  final baselineIds = ids(baseline);
  final random = Random(entries.length);
  for (var i = 0; i < shuffles; i++) {
    final shuffled = [...entries]..shuffle(random);
    final tree = DirectoryTree<int>.build(shuffled, options: options);
    expect(tree == baseline, isTrue, reason: 'shuffle $i');
    expect(tree.hashCode, baseline.hashCode, reason: 'shuffle $i');
    expect(ids(tree), baselineIds, reason: 'shuffle $i');
    expect(
      [for (final node in tree.nodes) node.path.toString()],
      [for (final node in baseline.nodes) node.path.toString()],
      reason: 'shuffle $i',
    );
  }
}

/// Structural invariants that hold for every tree.
void expectInvariants(DirectoryTree<int> tree) {
  final policy = tree.options.paths;
  final order = tree.options.order;
  int wrapped(TreeNode<Object?> a, TreeNode<Object?> b) {
    final result = order(a, b);
    return result != 0 ? result : a.id.value.compareTo(b.id.value);
  }

  // Every accepted entry appears exactly once, on a node at its path.
  final explicit = tree.nodes.where((node) => node.isExplicit).toList();
  expect(explicit, hasLength(tree.entries.length));
  final byEntry = Map<TreeEntry<int>, TreeNode<int>>.identity();
  for (final node in explicit) {
    expect(byEntry.containsKey(node.entry), isFalse);
    byEntry[node.entry!] = node;
  }
  for (final entry in tree.entries) {
    final node = byEntry[entry];
    expect(node, isNotNull, reason: entry.path);
    expect(node!.id, tree.idOf(entry.path));
    expect(node.kind, entry.kind);
  }

  final seenIds = <NodeId>{};
  for (var i = 0; i < tree.length; i++) {
    final node = tree.nodes[i];
    expect(seenIds.add(node.id), isTrue, reason: 'unique ids');
    expect(node.id, policy.idOf(node.path));
    expect(tree.indexOf(node.id), i);
    expect(tree[node.id], same(node));

    if (node.isRoot) {
      expect(node.depth, 0);
      expect(tree.roots, contains(node.id));
    } else {
      final parent = tree[node.parent!]!;
      expect(parent, isA<DirectoryNode<int>>());
      expect((parent as DirectoryNode<int>).children, contains(node.id));
      expect(node.depth, parent.depth + 1);
      expect(node.path.parent, parent.path);
      expect(node.label, node.name);
      expect(tree.isAncestor(parent.id, node.id), isTrue);
    }

    final size = tree.subtreeSizeOf(node.id);
    if (node is DirectoryNode<int>) {
      // Children follow in pre-order, each subtree packed after the last.
      var next = i + 1;
      for (final child in node.children) {
        expect(tree.indexOf(child), next);
        next += tree.subtreeSizeOf(child);
      }
      expect(next, i + size);
      expect(
        node.children,
        tree.childrenOf(node.id).map((child) => child.id).toList(),
      );
      final children = tree.childrenOf(node.id);
      for (var k = 1; k < children.length; k++) {
        expect(wrapped(children[k - 1], children[k]), lessThan(0));
      }
      if (!node.isExplicit && tree.options.roots == const TreeRoots.minimal()) {
        expect(node.hasChildren, isTrue, reason: 'inferred dirs hold entries');
      }
    } else {
      expect(size, 1);
    }
  }

  final roots = tree.rootNodes;
  for (var k = 1; k < roots.length; k++) {
    expect(wrapped(roots[k - 1], roots[k]), lessThan(0));
  }
  expect(roots.map((root) => root.label).toSet(), hasLength(roots.length));
}

bool isInside(
  TreeNode<Object?> node,
  TreeNode<Object?> ancestor,
  PathPolicy policy,
) {
  String fold(String text) => policy.caseSensitive ? text : text.toLowerCase();
  if (ancestor.path.isRoot) {
    return !node.path.isRoot &&
        fold(node.path.root) == fold(ancestor.path.root);
  }
  return node.id.value.startsWith('${ancestor.id.value}/');
}

/// Brute-force oracle for minimal roots and for the node set.
void expectMinimalOracle(DirectoryTree<int> tree) {
  final policy = tree.options.paths;
  final contributions = <NodeId, TreePath>{};
  for (final entry in tree.entries) {
    final path = policy.parse(entry.path);
    final contribution = entry.isFile ? path.parent! : path;
    contributions[policy.idOf(contribution)] = contribution;
  }
  final expectedRoots = <NodeId>{
    for (final MapEntry(key: id, value: path) in contributions.entries)
      if (!_hasAncestorIn(path, contributions, policy)) id,
  };
  expect(tree.roots.toSet(), expectedRoots);

  final expectedNodes = <NodeId>{};
  for (final entry in tree.entries) {
    for (
      TreePath? path = policy.parse(entry.path);
      path != null;
      path = path.parent
    ) {
      final id = policy.idOf(path);
      expectedNodes.add(id);
      if (expectedRoots.contains(id)) break;
    }
  }
  expect(ids(tree).toSet(), expectedNodes);

  for (final a in tree.rootNodes) {
    for (final b in tree.rootNodes) {
      if (!identical(a, b)) expect(isInside(a, b, policy), isFalse);
    }
  }
}

bool _hasAncestorIn(
  TreePath path,
  Map<NodeId, TreePath> contributions,
  PathPolicy policy,
) {
  for (var parent = path.parent; parent != null; parent = parent.parent) {
    if (contributions.containsKey(policy.idOf(parent))) return true;
  }
  return false;
}

void main() {
  group('determinism', () {
    test('50 shuffles of 2k entries build equal trees (case sensitive)', () {
      const options = TreeOptions();
      final entries = generateEntries(1, 2000, options.paths);
      expectDeterministic(entries, options, shuffles: 50);
      final tree = DirectoryTree<int>.build(entries, options: options);
      expect(tree.issues, isNotEmpty, reason: 'corpus exercises conflicts');
      expect(tree.length, greaterThan(2000));
      expectInvariants(tree);
      expectMinimalOracle(tree);
    });

    test('50 shuffles of 2k mixed-case entries build equal trees '
        '(case insensitive)', () {
      const options = TreeOptions(paths: PathPolicy.caseInsensitive);
      final entries = generateEntries(2, 2000, options.paths, mixedCase: true);
      expectDeterministic(entries, options, shuffles: 50);
      final tree = DirectoryTree<int>.build(entries, options: options);
      expectInvariants(tree);
      expectMinimalOracle(tree);
    });

    final strategies = <String, TreeRoots>{
      'commonAncestor': const TreeRoots.commonAncestor(),
      'filesystem': const TreeRoots.filesystem(),
      'fixed': const TreeRoots.fixed(['/home/u', 'c:/work/a', 'rel/b', '/x']),
    };
    strategies.forEach((name, roots) {
      test('$name roots are deterministic and consistent', () {
        final options = TreeOptions(
          paths: PathPolicy.caseInsensitive,
          roots: roots,
        );
        final entries = generateEntries(
          name.length,
          1000,
          options.paths,
          mixedCase: true,
        );
        expectDeterministic(entries, options, shuffles: 10);
        expectInvariants(DirectoryTree<int>.build(entries, options: options));
      });
    });

    test('alphabetical and custom comparators are deterministic', () {
      final bySize = TreeOrder.by<int>(
        (a, b) => (a.data ?? -1).compareTo(b.data ?? -1),
      );
      for (final order in [TreeOrder.alphabetical, bySize]) {
        final options = TreeOptions(order: order);
        final entries = generateEntries(3, 1000, options.paths);
        expectDeterministic(entries, options, shuffles: 10);
        expectInvariants(DirectoryTree<int>.build(entries, options: options));
      }
    });
  });
}
