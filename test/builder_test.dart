import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

const insensitive = TreeOptions(paths: PathPolicy.caseInsensitive);

List<String> paths(DirectoryTree<Object?> tree) => [
  for (final node in tree.nodes) node.path.toString(),
];

void main() {
  group('DirectoryTreeBuilder', () {
    test('starts empty or seeded, in order', () {
      expect(DirectoryTreeBuilder<int>().length, 0);
      final builder = DirectoryTreeBuilder<int>(
        entries: const [TreeEntry.file('/b'), TreeEntry.file('/a')],
      );
      expect(builder.entries, const [
        TreeEntry<int>.file('/b'),
        TreeEntry<int>.file('/a'),
      ]);
      expect(builder.options, const TreeOptions());
    });

    test('add replaces an entry with the same id in place', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addFile('/a', data: 1)
        ..addFile('/b')
        ..addFile('/a/', data: 2);
      expect(builder.length, 2);
      expect(builder.entries, const [
        TreeEntry<int>.file('/a/', data: 2),
        TreeEntry<int>.file('/b'),
      ]);
    });

    test('replacement follows the case policy', () {
      final builder = DirectoryTreeBuilder<int>(options: insensitive)
        ..addFile('/A/x.txt', data: 1)
        ..addFile('/z')
        ..addDirectory('/a/X.TXT', data: 2);
      expect(builder.entries, const [
        TreeEntry<int>.directory('/a/X.TXT', data: 2),
        TreeEntry<int>.file('/z'),
      ]);
    });

    test('addAll, addFile, and addDirectory', () {
      final builder = DirectoryTreeBuilder<String>()
        ..addAll(const [TreeEntry.file('/r/1')])
        ..addFile('/r/2', data: 'two')
        ..addDirectory('/r/d', data: 'dir');
      expect(builder.entries, const [
        TreeEntry<String>.file('/r/1'),
        TreeEntry<String>.file('/r/2', data: 'two'),
        TreeEntry<String>.directory('/r/d', data: 'dir'),
      ]);
    });

    test('contains compares by id and ignores inferred directories', () {
      final builder = DirectoryTreeBuilder<int>(options: insensitive)
        ..addFile('/Repo/a.txt');
      expect(builder.contains('/repo/A.TXT'), isTrue);
      expect(builder.contains(r'\REPO\a.txt'), isTrue);
      expect(builder.contains('/repo'), isFalse);
      expect(builder.contains(''), isFalse);
      expect(builder.contains('../x'), isFalse);
    });

    test('remove is recursive by default', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addDirectory('/a')
        ..addFile('/a/x')
        ..addFile('/a/b/y')
        ..addFile('/ab/z')
        ..addFile('/c');
      expect(builder.remove('/a'), 3);
      expect(builder.entries.map((entry) => entry.path), ['/ab/z', '/c']);
    });

    test('remove without recursion removes only the exact entry', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addDirectory('/a')
        ..addFile('/a/x');
      expect(builder.remove('/a', recursive: false), 1);
      expect(builder.entries.map((entry) => entry.path), ['/a/x']);
      expect(builder.remove('/a', recursive: false), 0);
    });

    test('remove counts inside entries even when the path is no entry', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addFile('/a/x')
        ..addFile('/a/y');
      expect(builder.remove('/a'), 2);
      expect(builder.length, 0);
    });

    test('remove follows the case policy', () {
      final builder = DirectoryTreeBuilder<int>(options: insensitive)
        ..addFile('/Repo/Lib/a.dart')
        ..addFile('/repo/README.md')
        ..addFile('/other/b');
      expect(builder.remove('/REPO'), 2);
      expect(builder.entries.map((entry) => entry.path), ['/other/b']);
    });

    test('remove of a path root removes that root only', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addDirectory('/')
        ..addFile('/a/x')
        ..addFile('C:/y')
        ..addFile('rel/z');
      expect(builder.remove('/'), 2);
      expect(builder.entries.map((entry) => entry.path), ['C:/y', 'rel/z']);
      expect(builder.remove('.'), 1);
      expect(builder.remove('c:'), 1);
      expect(builder.length, 0);
    });

    test('remove of an invalid path removes nothing', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addFile('')
        ..addFile('/a');
      expect(builder.remove(''), 0);
      expect(builder.remove('../a'), 0);
      expect(builder.length, 2);
    });

    test('removeWhere returns the count and keeps order', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addFile('/a', data: 1)
        ..addFile('/b', data: 2)
        ..addFile('/c', data: 3)
        ..addFile('/d', data: 4);
      expect(builder.removeWhere((entry) => entry.data!.isEven), 2);
      expect(builder.entries.map((entry) => entry.path), ['/a', '/c']);
    });

    test('clear removes every entry and keeps options', () {
      final builder = DirectoryTreeBuilder<int>(options: insensitive)
        ..addFile('/a')
        ..clear();
      expect(builder.length, 0);
      expect(builder.options, insensitive);
    });

    test('entries is an unmodifiable snapshot', () {
      final builder = DirectoryTreeBuilder<int>()..addFile('/a');
      final snapshot = builder.entries;
      builder.addFile('/b');
      expect(snapshot, hasLength(1));
      expect(
        () => snapshot.add(const TreeEntry.file('/c')),
        throwsUnsupportedError,
      );
    });

    test('invalid entries are kept in order and never merge', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addFile('')
        ..addFile('/ok')
        ..addFile('');
      expect(builder.length, 3);
      final tree = builder.build();
      expect(tree.issues.map((issue) => issue.kind), [
        TreeIssueKind.invalidPath,
        TreeIssueKind.invalidPath,
      ]);
      expect(tree.entries, const [TreeEntry<int>.file('/ok')]);
    });

    test('changing the path policy re-keys and merges entries', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addFile('/a', data: 1)
        ..addFile('/b')
        ..addFile('/A', data: 2);
      expect(builder.length, 3);
      builder.options = insensitive;
      expect(builder.entries, const [
        TreeEntry<int>.file('/A', data: 2),
        TreeEntry<int>.file('/b'),
      ]);
      expect(builder.contains('/a'), isTrue);
    });

    test('re-keying can turn invalid entries valid', () {
      final builder = DirectoryTreeBuilder<int>()..addFile('../ab');
      expect(builder.build().issues, hasLength(1));
      builder.options = TreeOptions(
        paths: PathPolicy(
          unicodeNormalizer: (path) => path.replaceAll('../', ''),
        ),
      );
      expect(builder.contains('ab'), isTrue);
      expect(builder.build().issues, isEmpty);
    });

    test('a raw NUL is rejected before the normalizer runs', () {
      final builder = DirectoryTreeBuilder<int>(
        options: TreeOptions(
          paths: PathPolicy(
            unicodeNormalizer: (path) => path.replaceAll('\u0000', ''),
          ),
        ),
      )..addFile('/a\u0000b');
      expect(builder.contains('/ab'), isFalse);
      expect(builder.build().issues.single.kind, TreeIssueKind.invalidPath);
    });

    test('changing only roots or order keeps keys', () {
      final builder = DirectoryTreeBuilder<int>()
        ..addFile('/a')
        ..addFile('/A');
      builder.options = builder.options.copyWith(
        roots: const TreeRoots.filesystem(),
        order: TreeOrder.alphabetical,
      );
      expect(builder.length, 2);
      expect(builder.build().rootNodes.single.name, '/');
    });

    test('build leaves the builder usable and trees independent', () {
      final builder = DirectoryTreeBuilder<int>()..addFile('/r/a');
      final first = builder.build();
      builder.addFile('/r/b');
      final second = builder.build();
      expect(first.fileCount, 1);
      expect(second.fileCount, 2);
      expect(builder.build(), second);
    });
  });

  group('conflicts', () {
    test('a file that is an ancestor of another entry becomes a directory', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/a/b', data: 1),
        TreeEntry.file('/a/b/c.txt', data: 2),
      ]);
      final b = tree.nodeAt('/a/b')!;
      expect(b.isDirectory, isTrue);
      expect(b.isExplicit, isFalse);
      expect(tree.childrenOf(b.id).single.name, 'c.txt');
      expect(tree.issues, const [
        TreeIssue<int>(
          kind: TreeIssueKind.conflict,
          path: '/a/b',
          entry: TreeEntry.file('/a/b', data: 1),
          message:
              'The file entry is an ancestor of another entry, so the path '
              'is a directory; the file entry was dropped.',
        ),
      ]);
      expect(tree.entries, const [TreeEntry<int>.file('/a/b/c.txt', data: 2)]);
    });

    test('conflicts do not depend on order and chain through levels', () {
      const entries = [
        TreeEntry<int>.file('/a/b/c'),
        TreeEntry<int>.file('/a/b'),
        TreeEntry<int>.file('/a'),
        TreeEntry<int>.file('/z'),
      ];
      final forward = DirectoryTree<int>.build(entries);
      final backward = DirectoryTree<int>.build(entries.reversed);
      expect(forward, backward);
      expect(forward.issues.map((issue) => issue.path), ['/a/b', '/a']);
      expect(backward.issues.map((issue) => issue.path), ['/a', '/a/b']);
      expect(forward.nodeAt('/a/b/c')!.isFile, isTrue);
      expect(forward.nodeAt('/a')!.isDirectory, isTrue);
      expect(
        forward.nodes.where((node) => node.isFile).map((node) => node.name),
        ['c', 'z'],
      );
    });

    test('a conflicting file no longer contributes a root', () {
      final tree = DirectoryTree.fromPaths(['/r/x', '/r/x/y.txt']);
      expect(tree.rootNodes.single.path.toString(), '/r/x');
    });

    test('directory entries with entries inside are not conflicts', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.directory('/a/b', data: 1),
        TreeEntry.file('/a/b/c.txt'),
      ]);
      expect(tree.issues, isEmpty);
      expect(tree.nodeAt('/a/b')!.data, 1);
    });

    test('conflicts follow the case policy', () {
      final tree = DirectoryTree.fromPaths([
        '/a/B',
        '/a/b/c.txt',
      ], options: insensitive);
      expect(tree.issues.single.kind, TreeIssueKind.conflict);
      expect(tree.issues.single.path, '/a/B');
      expect(tree.nodeAt('/A/B')!.isDirectory, isTrue);
    });

    test('a dropped file does not spell the directories above it', () {
      // '/q/R/a' is dropped because '/q/r/a/b' lies inside it, so only the
      // surviving entries may spell '/q/r'.
      final tree = DirectoryTree.fromPaths([
        '/q/R/a',
        '/q/r/a/b',
        '/q/x',
      ], options: insensitive);
      expect(tree.issues.single.path, '/q/R/a');
      expect(paths(tree), ['/q', '/q/r', '/q/r/a', '/q/r/a/b', '/q/x']);
      expect(tree.rebuild((_) {}), tree);
      expect(DirectoryTree.build(tree.entries, options: tree.options), tree);
    });

    test('rebuilding from the surviving entries reproduces the tree', () {
      // Few names in two spellings and a shallow depth, so many files are
      // ancestors of other entries and ancestors arrive in several
      // spellings.
      const names = ['a', 'A', 'b', 'B', 'c'];
      final random = Random(404);
      var conflicts = 0;
      for (var round = 0; round < 500; round++) {
        final entries = [
          for (var e = 1 + random.nextInt(8); e > 0; e--)
            (random.nextInt(4) == 0
                ? TreeEntry<int>.directory
                : TreeEntry<int>.file)(
              '/${[for (var d = 1 + random.nextInt(4); d > 0; d--) names[random.nextInt(names.length)]].join('/')}',
              data: e,
            ),
        ];
        for (final options in [insensitive, const TreeOptions()]) {
          final tree = DirectoryTree<int>.build(entries, options: options);
          conflicts += tree.issues
              .where((issue) => issue.kind == TreeIssueKind.conflict)
              .length;
          final reason = '$entries (${options.paths})';
          expect(tree.rebuild((_) {}), tree, reason: reason);
          expect(
            DirectoryTree<int>.build(tree.entries, options: options),
            tree,
            reason: reason,
          );
        }
      }
      // Guard against a generator that never produces conflicts.
      expect(conflicts, greaterThan(200));
    });
  });

  group('invalid paths', () {
    test('are reported in input order with their entries', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file(''),
        TreeEntry.file('/ok/a'),
        TreeEntry.file('bad\u0000'),
        TreeEntry.file('../up'),
        TreeEntry.file('/'),
        TreeEntry.file(r'C:\'),
        TreeEntry.directory('D:'),
        TreeEntry.directory('//srv/share'),
      ]);
      expect(tree.issues.map((issue) => (issue.kind, issue.path)), [
        (TreeIssueKind.invalidPath, ''),
        (TreeIssueKind.invalidPath, 'bad\u0000'),
        (TreeIssueKind.invalidPath, '../up'),
        (TreeIssueKind.invalidPath, '/'),
        (TreeIssueKind.invalidPath, r'C:\'),
      ]);
      expect(tree.issues.map((issue) => issue.message), [
        'Path is empty; the entry was skipped.',
        'Path contains a NUL character; the entry was skipped.',
        'Relative path escapes its root; the entry was skipped.',
        'A file entry cannot be a path root; the entry was skipped.',
        'A file entry cannot be a path root; the entry was skipped.',
      ]);
      expect(tree.issues.first.entry, const TreeEntry<int>.file(''));
      expect(tree.nodeAt('D:')!.isExplicit, isTrue);
      expect(tree.nodeAt('//srv/share')!.isExplicit, isTrue);
    });

    test('a later directory entry for a path root replaces the file', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/'),
        TreeEntry.directory('/'),
      ]);
      expect(tree.issues, isEmpty);
      expect(tree.rootNodes.single.isExplicit, isTrue);
    });

    test('mixed issue kinds are ordered by entry position', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/x/y'),
        TreeEntry.file(''),
        TreeEntry.file('/x/y/z'),
        TreeEntry.file('..'),
      ]);
      expect(tree.issues.map((issue) => (issue.kind, issue.path)), [
        (TreeIssueKind.conflict, '/x/y'),
        (TreeIssueKind.invalidPath, ''),
        (TreeIssueKind.invalidPath, '..'),
      ]);
    });
  });

  group('duplicate ids', () {
    test('the last entry wins at the first position', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a', data: 1),
        TreeEntry.file('/r/b'),
        TreeEntry.file('/r/a', data: 2),
      ]);
      expect(tree.entries, const [
        TreeEntry<int>.file('/r/a', data: 2),
        TreeEntry<int>.file('/r/b'),
      ]);
      expect(tree.nodeAt('/r/a')!.data, 2);
      expect(tree.issues, isEmpty);
    });

    test('a later entry can change the kind', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a'),
        TreeEntry.directory('/r/a'),
      ]);
      expect(tree.nodeAt('/r/a')!.isDirectory, isTrue);
    });

    test('case-insensitive duplicates merge and keep the last spelling', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/README.md', data: 1),
        TreeEntry.file('/r/readme.MD', data: 2),
      ], options: insensitive);
      expect(tree.files.single.name, 'readme.MD');
      expect(tree.files.single.data, 2);
    });
  });

  group('display spelling', () {
    List<String> shuffledPaths(
      List<TreeEntry<int>> entries,
      TreeOptions options,
    ) {
      final random = Random(7);
      final expected = paths(
        DirectoryTree<int>.build(entries, options: options),
      );
      for (var i = 0; i < 50; i++) {
        final shuffled = [...entries]..shuffle(random);
        expect(
          paths(DirectoryTree<int>.build(shuffled, options: options)),
          expected,
        );
      }
      return expected;
    }

    test('inferred directories use the smallest spelling per segment', () {
      final result = shuffledPaths(const [
        TreeEntry.file('/Work/Lib/a.dart'),
        TreeEntry.file('/work/lib/b.dart'),
        TreeEntry.file('/WORK/lib/C.dart'),
      ], insensitive);
      expect(result, [
        '/WORK/Lib',
        '/WORK/Lib/a.dart',
        '/WORK/Lib/b.dart',
        '/WORK/Lib/C.dart',
      ]);
    });

    test('an entry spells its own node and children extend it', () {
      final result = shuffledPaths(const [
        TreeEntry.file('/Work/Lib/a.dart'),
        TreeEntry.file('/work/lib/b.dart'),
        TreeEntry.directory('/work/LIB'),
      ], insensitive);
      expect(result, ['/work/LIB', '/work/LIB/a.dart', '/work/LIB/b.dart']);
    });

    test('non-root inferred directories are spelled the same way', () {
      final result = shuffledPaths(const [
        TreeEntry.file('/p/z.txt'),
        TreeEntry.file('/p/docs/y.md'),
        TreeEntry.file('/p/Docs/x.md'),
        TreeEntry.file('/P/dOCS/w.md'),
      ], insensitive);
      // 'P' (0x50) sorts before 'p'; 'Docs' before 'dOCS' and 'docs'.
      expect(result, [
        '/P',
        '/P/Docs',
        '/P/Docs/w.md',
        '/P/Docs/x.md',
        '/P/Docs/y.md',
        '/P/z.txt',
      ]);
    });

    test('UNC servers and shares merge across case', () {
      final tree = DirectoryTree.fromPaths([
        r'\\Server\Share\a.txt',
        '//server/share/b.txt',
      ], options: insensitive);
      expect(tree.roots, hasLength(1));
      expect(tree.rootNodes.single.path.toString(), '//Server/Share/');
      expect(tree.fileCount, 2);
    });
  });
}
