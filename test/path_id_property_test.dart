import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/src/path/case_folding.dart';
import 'package:test/test.dart';

/// Composes `e` plus COMBINING ACUTE ACCENT into `é`: a pure, idempotent
/// stand-in for NFC normalization.
String composeAcute(String path) => path.replaceAll('e\u0301', '\u00e9');

/// Every policy the invariants must hold under.
final Map<String, PathPolicy> policies = {
  'default': const PathPolicy(),
  'case-insensitive': PathPolicy.caseInsensitive,
  'backslash is not a separator': const PathPolicy(backslashIsSeparator: false),
  'case-insensitive, backslash is not a separator': const PathPolicy(
    caseSensitive: false,
    backslashIsSeparator: false,
  ),
  'case-insensitive with a normalizer': const PathPolicy(
    caseSensitive: false,
    unicodeNormalizer: composeAcute,
  ),
};

/// First segments that are, or fold to, drive specs, mixed with drive
/// paths, other roots, and ordinary relative names.
const List<String> firsts = [
  'K:',
  'k:',
  '\u212A:',
  'S:',
  's:',
  '\u017F:',
  '\u017F:x',
  './K:',
  './\u212A:',
  './\u017F:',
  'K:x',
  '\u212A',
  'C:',
  '/',
  '//srv/share',
  'a',
  'A',
  'e\u0301',
  '\u00e9',
];

const List<String> names = [
  'x',
  'X',
  'a.txt',
  'A.TXT',
  'b',
  '\u212A',
  'k',
  'K:',
  '\u212A:',
  'e\u0301',
];

/// A random path whose first segment comes from [firsts].
String randomPath(Random random) {
  final buffer = StringBuffer(firsts[random.nextInt(firsts.length)]);
  final depth = random.nextInt(4);
  for (var i = 0; i < depth; i++) {
    if (!buffer.toString().endsWith('/')) {
      buffer.write(random.nextInt(4) == 0 ? r'\' : '/');
    }
    buffer.write(names[random.nextInt(names.length)]);
  }
  return buffer.toString();
}

/// Whether the parsed [entry] lies at or below the parsed [target] under
/// [policy], decided from roots and segments, never from canonical strings
/// or ids.
bool isAtOrBelow(TreePath entry, TreePath target, PathPolicy policy) {
  String key(String text) => policy.caseSensitive ? text : foldCase(text);
  if (key(entry.root) != key(target.root)) return false;
  final inner = entry.segments;
  final outer = target.segments;
  if (inner.length < outer.length) return false;
  for (var i = 0; i < outer.length; i++) {
    if (key(inner[i]) != key(outer[i])) return false;
  }
  return true;
}

/// Whether [a] and [b] are the same path under [policy], decided
/// structurally like [isAtOrBelow].
bool samePath(TreePath a, TreePath b, PathPolicy policy) =>
    a.segments.length == b.segments.length && isAtOrBelow(a, b, policy);

/// Checks every id invariant of [tree] built under [policy].
void expectTreeInvariants(DirectoryTree<Object?> tree, PathPolicy policy) {
  final ids = <NodeId>{};
  for (final node in tree.nodes) {
    expect(ids.add(node.id), isTrue, reason: 'duplicate id ${node.id}');
    expect(node.id, policy.idOf(node.path), reason: '${node.path}');
    expect(tree[node.id], same(node), reason: '${node.path}');
    expect(
      tree.nodeAt(node.path.toString()),
      same(node),
      reason: 'nodeAt(${node.path})',
    );
    expect(
      policy.parse(node.path.toString()),
      node.path,
      reason: 'round trip of ${node.path}',
    );
  }
  for (final entry in tree.entries) {
    final node = tree.nodeAt(entry.path);
    expect(node, isNotNull, reason: 'entry ${entry.path}');
    expect(
      samePath(node!.path, policy.parse(entry.path), policy),
      isTrue,
      reason: '${entry.path} found ${node.path}',
    );
  }
}

void main() {
  group('drive-like first segments under every policy', () {
    policies.forEach((name, policy) {
      final options = TreeOptions(paths: policy);
      test('$name: ids, lookups, and builder edits stay consistent', () {
        for (var seed = 0; seed < 150; seed++) {
          final random = Random(seed);
          final paths = [
            for (var i = 0; i < 1 + random.nextInt(8); i++) randomPath(random),
          ];
          final reason = 'seed $seed: $paths';
          final DirectoryTree<Object?> tree;
          try {
            tree = DirectoryTree.fromPaths(paths, options: options);
          } on Object catch (error) {
            fail('building threw $error; $reason');
          }
          expectTreeInvariants(tree, policy);

          // The builder keys entries by id: one entry per distinct path.
          final builder = DirectoryTreeBuilder<Object?>(
            options: options,
            entries: [for (final path in paths) TreeEntry.file(path)],
          );
          final parsed = <TreePath>[];
          for (final path in paths) {
            final target = policy.parse(path);
            if (!parsed.any((other) => samePath(other, target, policy))) {
              parsed.add(target);
            }
          }
          expect(builder.length, parsed.length, reason: reason);

          final probe = policy.parse(randomPath(random));
          expect(
            builder.contains(probe.toString()),
            parsed.any((path) => samePath(path, probe, policy)),
            reason: 'contains($probe); $reason',
          );
          expect(
            builder.remove(probe.toString()),
            parsed.where((path) => isAtOrBelow(path, probe, policy)).length,
            reason: 'remove($probe); $reason',
          );
        }
      });
    });
  });

  group('a folded drive letter is not a drive', () {
    const policy = PathPolicy.caseInsensitive;
    const options = TreeOptions(paths: policy);

    test('the Kelvin sign drive-like segment gets the ./ prefix', () {
      final path = TreePath.parse('\u212A:/x');
      expect(path.root, '');
      expect(path.segments, ['\u212A:', 'x']);
      expect(path.toString(), './\u212A:/x');
      expect(TreePath.parse(path.toString()), path);
      expect(policy.idOf(path), isNot(policy.idOf(TreePath.parse('K:/x'))));
      expect(TreePath.parse('.').child('\u017F:').toString(), './\u017F:');
      // Only one code point before the colon makes a drive-like segment.
      expect(TreePath.parse('\u017F:x').toString(), '\u017F:x');
      expect(TreePath.parse('\u212A\u212A:').toString(), '\u212A\u212A:');
    });

    test('K:/x and \u212A:/x build separate nodes with unique ids', () {
      final tree = DirectoryTree.fromPaths([
        'K:/x/a.txt',
        '\u212A:/x/b.txt',
      ], options: options);
      expect(
        tree.nodes.map((node) => node.path.toString()),
        unorderedEquals([
          'K:/x',
          'K:/x/a.txt',
          './\u212A:/x',
          './\u212A:/x/b.txt',
        ]),
      );
      expectTreeInvariants(tree, policy);
      expect(tree.nodeAt('K:/x/b.txt'), isNull);
    });

    test('K:/x/a.txt and \u212A:/x/a.txt stay two files', () {
      final tree = DirectoryTree.fromPaths([
        'K:/x/a.txt',
        '\u212A:/x/a.txt',
      ], options: options);
      expect(tree.fileCount, 2);
      expectTreeInvariants(tree, policy);
    });

    test('S:/x and \u017F:/x stay apart', () {
      final tree = DirectoryTree.fromPaths([
        'S:/x/a.txt',
        '\u017F:/x/a.txt',
      ], options: options);
      expect(tree.fileCount, 2);
      expectTreeInvariants(tree, policy);
    });

    test('the builder neither finds nor removes the relative entry', () {
      final builder = DirectoryTreeBuilder<Object?>(options: options)
        ..addFile('\u212A:/x/b.txt');
      expect(builder.contains('K:/x/b.txt'), isFalse);
      expect(builder.contains('./k:/x/b.txt'), isTrue);
      expect(builder.remove('K:/x'), 0);
      expect(builder.length, 1);
      expect(builder.remove('./K:/x'), 1);
    });

    test('./K: and \u212A: merge as one relative directory', () {
      final tree = DirectoryTree.fromPaths([
        './K:/x/a.txt',
        '\u212A:/x/b.txt',
      ], options: options);
      expect(tree.nodes.map((node) => node.path.toString()), [
        './K:/x',
        './K:/x/a.txt',
        './K:/x/b.txt',
      ]);
      expectTreeInvariants(tree, policy);
    });
  });
}
