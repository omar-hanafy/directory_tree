import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

const corpus = <TreeEntry<int>>[
  TreeEntry.file('/home/me/repo/lib/a.dart'),
  TreeEntry.file('/home/me/repo/lib/src/b.dart'),
  TreeEntry.directory('/home/me/repo/assets'),
  TreeEntry.file('/home/me/notes/todo.md'),
  TreeEntry.file('C:/proj/x/main.c'),
  TreeEntry.file(r'c:\proj\y\util.c'),
  TreeEntry.file(r'\\srv\share\docs\spec.pdf'),
  TreeEntry.file('rel/one.txt'),
  TreeEntry.file('rel/two/three.txt'),
];

DirectoryTree<int> buildWith(
  TreeRoots roots, [
  List<TreeEntry<int>>? entries,
]) => DirectoryTree<int>.build(
  entries ?? corpus,
  options: TreeOptions(roots: roots),
);

List<String> rootPaths(DirectoryTree<Object?> tree) => [
  for (final node in tree.rootNodes) node.path.toString(),
];

List<String> labels(DirectoryTree<Object?> tree) => [
  for (final node in tree.rootNodes) node.label,
];

void main() {
  group('TreeRoots.minimal', () {
    test('uses the outermost contributions', () {
      final tree = buildWith(const TreeRoots.minimal());
      expect(rootPaths(tree), [
        '/home/me/repo/assets',
        '//srv/share/docs',
        '/home/me/repo/lib',
        '/home/me/notes',
        'rel',
        'C:/proj/x',
        'C:/proj/y',
      ]);
      expect(tree.nodeAt('/home/me/repo/lib/src')!.depth, 1);
      expect(tree.nodeAt('rel/two')!.parent, tree.idOf('rel'));
      expect(tree.nodeAt('/home/me/repo'), isNull);
      expect(tree.issues, isEmpty);
      expect(tree.fileCount, 8);
    });

    test('a directory entry above other contributions takes over', () {
      final tree = buildWith(const TreeRoots.minimal(), [
        ...corpus,
        const TreeEntry.directory('/home'),
      ]);
      expect(rootPaths(tree), contains('/home'));
      expect(rootPaths(tree), isNot(contains('/home/me/notes')));
      expect(tree.nodeAt('/home')!.isExplicit, isTrue);
    });

    test('files directly in a path root use that root', () {
      final tree = DirectoryTree.fromPaths(['/a.txt', 'C:/b.txt', 'c.txt']);
      expect(rootPaths(tree), ['.', '/', 'C:/']);
      expect(labels(tree), ['.', '/', 'C:']);
    });
  });

  group('TreeRoots.commonAncestor', () {
    test('uses one root per path root at the deepest common directory', () {
      final tree = buildWith(const TreeRoots.commonAncestor());
      expect(rootPaths(tree), [
        '//srv/share/docs',
        '/home/me',
        'C:/proj',
        'rel',
      ]);
      expect(tree.nodeAt('/home/me')!.isExplicit, isFalse);
      expect(tree.childrenOf(tree.idOf('/home/me')!).map((node) => node.name), [
        'notes',
        'repo',
      ]);
    });

    test('stops at a contribution even with a single child', () {
      final tree = buildWith(const TreeRoots.commonAncestor(), const [
        TreeEntry.directory('/a/b'),
        TreeEntry.file('/a/b/c/d.txt'),
      ]);
      expect(rootPaths(tree), ['/a/b']);
    });

    test('drives and shares are separate groups', () {
      final tree = DirectoryTree.fromPaths([
        'C:/a/x.txt',
        'D:/a/y.txt',
        '//s/one/z',
        '//s/two/z',
      ], options: const TreeOptions(roots: TreeRoots.commonAncestor()));
      expect(rootPaths(tree), ['//s/one/', '//s/two/', 'C:/a', 'D:/a']);
    });
  });

  group('TreeRoots.fixed', () {
    test('uses exactly the given roots and drops entries outside', () {
      final tree = buildWith(
        const TreeRoots.fixed(['/home/me/repo', r'C:\proj', '/nowhere']),
      );
      expect(rootPaths(tree), ['/nowhere', 'C:/proj', '/home/me/repo']);
      expect(tree.nodeAt('/nowhere')!.isExplicit, isFalse);
      expect(
        tree.childrenOf(tree.idOf('/nowhere')!),
        isEmpty,
        reason: 'fixed roots exist even when empty',
      );
      expect(tree.issues.map((issue) => (issue.kind, issue.path)), [
        (TreeIssueKind.outsideRoots, '/home/me/notes/todo.md'),
        (TreeIssueKind.outsideRoots, r'\\srv\share\docs\spec.pdf'),
        (TreeIssueKind.outsideRoots, 'rel/one.txt'),
        (TreeIssueKind.outsideRoots, 'rel/two/three.txt'),
      ]);
      expect(
        tree.issues.first.message,
        'The entry is outside every fixed root; the entry was dropped.',
      );
      expect(tree.entries, hasLength(5));
    });

    test('invalid root paths are reported without an entry', () {
      final tree = buildWith(const TreeRoots.fixed(['', '../x', '/ok']), []);
      expect(rootPaths(tree), ['/ok']);
      expect(tree.issues, const [
        TreeIssue<int>(
          kind: TreeIssueKind.invalidPath,
          path: '',
          message: 'Path is empty; the root was ignored.',
        ),
        TreeIssue<int>(
          kind: TreeIssueKind.invalidPath,
          path: '../x',
          message: 'Relative path escapes its root; the root was ignored.',
        ),
      ]);
    });

    test('root issues come before entry issues', () {
      final tree = buildWith(const TreeRoots.fixed(['/a', '']), const [
        TreeEntry.file(''),
        TreeEntry.file('/b/x'),
      ]);
      expect(tree.issues.map((issue) => (issue.kind, issue.entry)), [
        (TreeIssueKind.invalidPath, null),
        (TreeIssueKind.invalidPath, const TreeEntry<int>.file('')),
        (TreeIssueKind.outsideRoots, const TreeEntry<int>.file('/b/x')),
      ]);
    });

    test('nested roots collapse into the outermost', () {
      final tree = buildWith(const TreeRoots.fixed(['/a/b/c', '/a', '/a/b']), [
        const TreeEntry.file('/a/b/c/d.txt'),
      ]);
      expect(rootPaths(tree), ['/a']);
      expect(tree.nodeAt('/a/b')!.isExplicit, isFalse);
      expect(tree.nodeAt('/a/b/c/d.txt')!.depth, 3);
    });

    test('collapsed roots without entries do not appear', () {
      final tree = buildWith(const TreeRoots.fixed(['/a', '/a/empty']), []);
      expect(rootPaths(tree), ['/a']);
      expect(tree.length, 1);
    });

    test('duplicates merge and keep the smallest spelling', () {
      final tree = DirectoryTree<int>.build(
        const [TreeEntry.file('/repo/a.txt')],
        options: const TreeOptions(
          paths: PathPolicy.caseInsensitive,
          roots: TreeRoots.fixed(['/repo', '/Repo', '/REPO/']),
        ),
      );
      expect(rootPaths(tree), ['/REPO']);
      expect(tree.nodes.map((node) => node.path.toString()), [
        '/REPO',
        '/REPO/a.txt',
      ]);
    });

    test('a directory entry may equal a root; a file entry may not', () {
      final tree = buildWith(const TreeRoots.fixed(['/a', '/b']), const [
        TreeEntry.directory('/a', data: 1),
        TreeEntry.file('/b', data: 2),
        TreeEntry.file('/b/x.txt'),
      ]);
      expect(tree.nodeAt('/a')!.data, 1);
      expect(tree.nodeAt('/b')!.isDirectory, isTrue);
      expect(tree.nodeAt('/b')!.isExplicit, isFalse);
      expect(tree.issues.single.kind, TreeIssueKind.conflict);
      expect(
        tree.issues.single.entry,
        const TreeEntry<int>.file('/b', data: 2),
      );
      expect(
        tree.issues.single.message,
        'The file entry equals a fixed root, which is always a directory; '
        'the file entry was dropped.',
      );
    });

    test('root membership follows the case policy', () {
      final tree = DirectoryTree<int>.build(
        const [TreeEntry.file('/repo/A.txt')],
        options: const TreeOptions(
          paths: PathPolicy.caseInsensitive,
          roots: TreeRoots.fixed(['/Repo']),
        ),
      );
      expect(tree.nodes.map((node) => node.path.toString()), [
        '/Repo',
        '/Repo/A.txt',
      ]);
    });

    test('a path root can be a fixed root', () {
      final tree = buildWith(const TreeRoots.fixed(['/']));
      expect(rootPaths(tree), ['/']);
      expect(tree.nodeAt('/home/me')!.isExplicit, isFalse);
      expect(tree.issues, hasLength(5));
    });

    test('an empty root list drops every entry', () {
      final tree = buildWith(const TreeRoots.fixed([]));
      expect(tree.isEmpty, isTrue);
      expect(tree.issues, hasLength(corpus.length));
    });
  });

  group('TreeRoots.filesystem', () {
    test('uses path roots and materializes every ancestor', () {
      final tree = buildWith(const TreeRoots.filesystem());
      expect(rootPaths(tree), ['.', '/', '//srv/share/', 'C:/']);
      expect(labels(tree), ['.', '/', '//srv/share', 'C:']);
      for (final path in ['/home', '/home/me', '/home/me/repo', 'C:/proj']) {
        expect(tree.nodeAt(path)!.isExplicit, isFalse, reason: path);
      }
      expect(tree.nodeAt('/home')!.depth, 1);
      expect(tree.nodeAt('rel/two/three.txt')!.depth, 3);
    });

    test('a directory entry for a path root makes it explicit', () {
      final tree = buildWith(const TreeRoots.filesystem(), const [
        TreeEntry.directory('/', data: 9),
        TreeEntry.file('/a'),
      ]);
      expect(tree.rootNodes.single.data, 9);
    });
  });

  group('value semantics', () {
    test('== and hashCode', () {
      expect(const TreeRoots.minimal(), const TreeRoots.minimal());
      expect(
        const TreeRoots.fixed(['/a', '/b']),
        TreeRoots.fixed(['/a', '/${'b'}']),
      );
      expect(
        const TreeRoots.fixed(['/a']).hashCode,
        TreeRoots.fixed(['/${'a'}']).hashCode,
      );
      expect(const TreeRoots.fixed(['/a']), isNot(const TreeRoots.fixed([])));
      expect(
        const TreeRoots.minimal(),
        isNot(const TreeRoots.commonAncestor()),
      );
      expect(const TreeRoots.fixed([]), isNot(const TreeRoots.minimal()));
    });

    test('toString', () {
      expect(const TreeRoots.minimal().toString(), 'TreeRoots.minimal()');
      expect(
        const TreeRoots.commonAncestor().toString(),
        'TreeRoots.commonAncestor()',
      );
      expect(const TreeRoots.filesystem().toString(), 'TreeRoots.filesystem()');
      expect(
        const TreeRoots.fixed(['/a', '/b']).toString(),
        'TreeRoots.fixed(/a, /b)',
      );
    });
  });

  group('root labels', () {
    test('colliding names get the shortest unique trailing path', () {
      final tree = DirectoryTree.fromPaths(['/x/a/src/1', '/y/b/src/2']);
      expect(tree.rootNodes.map((node) => node.name), ['src', 'src']);
      expect(labels(tree), ['a/src', 'b/src']);
    });

    test('labels grow only while they still collide', () {
      final tree = DirectoryTree.fromPaths([
        '/p/a/src/1',
        '/q/a/src/2',
        '/r/b/src/3',
        '/r/lib/4',
      ]);
      expect(labels(tree), ['lib', 'p/a/src', 'q/a/src', 'b/src']);
    });

    test('drive-vs-drive collisions fall back to the full path', () {
      final tree = DirectoryTree.fromPaths(['C:/src/1', 'D:/src/2']);
      expect(labels(tree), ['C:/src', 'D:/src']);
    });

    test('a shorter path falls back while the longer one grows', () {
      final tree = DirectoryTree.fromPaths(['src/1', '/x/src/2']);
      expect(labels(tree), ['x/src', 'src']);
    });

    test('a trailing label never equals another root full path', () {
      final tree = DirectoryTree.fromPaths(['C:/src/1', '/foo/C:/src/2']);
      expect(labels(tree), ['foo/C:/src', 'C:/src']);
      expect(labels(tree).toSet(), hasLength(2));
    });

    test('non-root nodes keep their names as labels', () {
      final tree = DirectoryTree.fromPaths(['/x/a/src/f', '/y/b/src/f']);
      for (final node in tree.nodes.where((node) => !node.isRoot)) {
        expect(node.label, node.name);
      }
    });
  });
}
