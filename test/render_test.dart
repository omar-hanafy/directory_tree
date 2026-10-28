import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

/// Hand-checked tree (case sensitive, minimal roots, directories first):
///
/// ```text
/// /other            (inferred)
///   q.md
/// /r                (inferred)
///   a               (inferred)
///     x.txt
///     y.txt
///   b               (explicit directory entry)
///     c             (inferred)
///       z.txt
///   top.txt
/// ```
DirectoryTree<int> sampleTree() => DirectoryTree<int>.build([
  const TreeEntry.file('/r/a/x.txt', data: 1),
  const TreeEntry.file('/r/a/y.txt', data: 2),
  const TreeEntry.directory('/r/b', data: 3),
  const TreeEntry.file('/r/b/c/z.txt', data: 4),
  const TreeEntry.file('/r/top.txt', data: 5),
  const TreeEntry.file('/other/q.md', data: 6),
]);

/// Joins golden lines the way render does.
String lines(List<String> lines) => lines.join('\n');

TreeFilter names(Set<String> names) =>
    TreeFilter.where<Object?>((node) => names.contains(node.name));

void main() {
  final tree = sampleTree();

  group('styles', () {
    test('unicode is the default', () {
      final expected = lines([
        'other/',
        '└── q.md',
        'r/',
        '├── a/',
        '│   ├── x.txt',
        '│   └── y.txt',
        '├── b/',
        '│   └── c/',
        '│       └── z.txt',
        '└── top.txt',
      ]);
      expect(tree.render(), expected);
      expect(tree.render(style: TreeStyle.unicode), expected);
    });

    test('ascii', () {
      expect(
        tree.render(style: TreeStyle.ascii),
        lines([
          'other/',
          '`-- q.md',
          'r/',
          '|-- a/',
          '|   |-- x.txt',
          '|   `-- y.txt',
          '|-- b/',
          '|   `-- c/',
          '|       `-- z.txt',
          '`-- top.txt',
        ]),
      );
    });

    test('indent', () {
      expect(
        tree.render(style: TreeStyle.indent),
        lines([
          'other/',
          '  q.md',
          'r/',
          '  a/',
          '    x.txt',
          '    y.txt',
          '  b/',
          '    c/',
          '      z.txt',
          '  top.txt',
        ]),
      );
    });

    test('a custom style, including empty connectors', () {
      const custom = TreeStyle(
        branch: '+-- ',
        lastBranch: "'-- ",
        pipe: ':   ',
        gap: '    ',
      );
      expect(
        tree.render(style: custom),
        lines([
          'other/',
          "'-- q.md",
          'r/',
          '+-- a/',
          ':   +-- x.txt',
          ":   '-- y.txt",
          '+-- b/',
          ":   '-- c/",
          ":       '-- z.txt",
          "'-- top.txt",
        ]),
      );
      const bare = TreeStyle(branch: '', lastBranch: '', pipe: '', gap: '');
      expect(
        tree.render(style: bare, maxDepth: 1),
        lines(['other/', 'q.md', 'r/', 'a/', 'b/', 'top.txt']),
      );
    });

    test('the presets match the TreeStyle documentation', () {
      final small = DirectoryTree.fromPaths([
        '/repo/lib/main.dart',
        '/repo/README.md',
      ]);
      expect(
        small.render(),
        lines(['repo/', '├── lib/', '│   └── main.dart', '└── README.md']),
      );
      expect(
        small.render(style: TreeStyle.ascii),
        lines(['repo/', '|-- lib/', '|   `-- main.dart', '`-- README.md']),
      );
      expect(
        small.render(style: TreeStyle.indent),
        lines(['repo/', '  lib/', '    main.dart', '  README.md']),
      );
    });
  });

  group('content', () {
    test('multiple roots with colliding labels', () {
      final colliding = DirectoryTree.fromPaths([
        '/x/a/src/lib/f.dart',
        '/x/a/src/g.dart',
        '/y/b/src/h.dart',
      ]);
      expect(
        colliding.render(),
        lines([
          'a/src/',
          '├── lib/',
          '│   └── f.dart',
          '└── g.dart',
          'b/src/',
          '└── h.dart',
        ]),
      );
    });

    test('drive roots fall back to full paths', () {
      final drives = DirectoryTree.fromPaths(['C:/w/a.txt', 'D:/w/b.txt']);
      expect(
        drives.render(),
        lines(['C:/w/', '└── a.txt', 'D:/w/', '└── b.txt']),
      );
    });

    test('maxDepth omits deeper rows and keeps the connectors', () {
      expect(tree.render(maxDepth: 0), lines(['other/', 'r/']));
      expect(
        tree.render(maxDepth: 1),
        lines(['other/', '└── q.md', 'r/', '├── a/', '├── b/', '└── top.txt']),
      );
      expect(
        tree.render(maxDepth: 2),
        lines([
          'other/',
          '└── q.md',
          'r/',
          '├── a/',
          '│   ├── x.txt',
          '│   └── y.txt',
          '├── b/',
          '│   └── c/',
          '└── top.txt',
        ]),
      );
      expect(tree.render(maxDepth: 3), tree.render());
      expect(tree.render(maxDepth: 100), tree.render());
    });

    test('a negative maxDepth renders nothing', () {
      expect(tree.render(maxDepth: -1), '');
    });

    test('collapsed directories show without their children', () {
      expect(
        tree.render(expansion: const ExpansionState.collapsed()),
        lines(['other/', 'r/']),
      );
      expect(
        tree.render(
          expansion: ExpansionState.withCollapsed([tree.idOf('/r/a')!]),
        ),
        lines([
          'other/',
          '└── q.md',
          'r/',
          '├── a/',
          '├── b/',
          '│   └── c/',
          '│       └── z.txt',
          '└── top.txt',
        ]),
      );
    });

    test('compact folders', () {
      expect(
        tree.render(compactFolders: true),
        lines([
          'other/',
          '└── q.md',
          'r/',
          '├── a/',
          '│   ├── x.txt',
          '│   └── y.txt',
          '├── b/c/',
          '│   └── z.txt',
          '└── top.txt',
        ]),
      );
    });

    test('the POSIX root keeps a single slash', () {
      final posix = DirectoryTree.fromPaths([
        '/usr/lib/x.so',
        '/usr/lib/y.so',
      ], options: const TreeOptions(roots: TreeRoots.filesystem()));
      expect(
        posix.render(),
        lines([
          '/',
          '└── usr/',
          '    └── lib/',
          '        ├── x.so',
          '        └── y.so',
        ]),
      );
      expect(
        posix.render(compactFolders: true),
        lines(['/usr/lib/', '├── x.so', '└── y.so']),
      );
    });

    test('a filter shows matches with their ancestors, revealed', () {
      expect(
        tree.render(
          expansion: const ExpansionState.collapsed(),
          filter: names({'z.txt', 'q.md'}),
        ),
        lines([
          'other/',
          '└── q.md',
          'r/',
          '└── b/',
          '    └── c/',
          '        └── z.txt',
        ]),
      );
      expect(
        tree.render(filter: names({'z.txt'}), compactFolders: true),
        lines(['r/', '└── b/c/', '    └── z.txt']),
      );
      expect(tree.render(filter: names({})), '');
      expect(tree.render(filter: TreeFilter.all), tree.render());
    });

    test('a custom label callback receives typed rows', () {
      final seen = <String>[];
      final text = tree.render(
        maxDepth: 1,
        label: (row) {
          seen.add(row.id.value);
          final int? data = row.node.data;
          return '${row.label} [${row.isMatch ? 'match' : '-'}] $data';
        },
      );
      expect(
        text,
        lines([
          'other [match] null',
          '└── q.md [match] 6',
          'r [match] null',
          '├── a [match] null',
          '├── b [match] 3',
          '└── top.txt [match] 5',
        ]),
      );
      expect(seen, [
        '/other',
        '/other/q.md',
        '/r',
        '/r/a',
        '/r/b',
        '/r/top.txt',
      ]);
      final compacted = tree.render(
        compactFolders: true,
        maxDepth: 1,
        label: (row) => row.chain.map((node) => node.name).join(' > '),
      );
      expect(compacted, contains('├── b > c'));
    });

    test('an empty tree renders the empty string', () {
      expect(DirectoryTree<int>.empty().render(), '');
      expect(DirectoryTree<int>.empty().render(maxDepth: 0), '');
    });

    test('there is never a trailing newline', () {
      expect(tree.render().endsWith('\n'), isFalse);
      final single = DirectoryTree.fromPaths(['/p/only.txt']);
      expect(single.render(), lines(['p/', '└── only.txt']));
    });

    test('the DirectoryTree.render documentation example', () {
      final repo = DirectoryTree.fromPaths([
        '/repo/lib/main.dart',
        '/repo/lib/src/tree.dart',
        '/repo/README.md',
      ]);
      expect(
        repo.render(),
        lines([
          'repo/',
          '├── lib/',
          '│   ├── src/',
          '│   │   └── tree.dart',
          '│   └── main.dart',
          '└── README.md',
        ]),
      );
      var rows = repo.flatten(expansion: const ExpansionState.collapsed());
      expect(rows.map((row) => row.label), ['repo']);
      rows = rows.toggleNode(rows.first.id);
      expect(rows.map((row) => row.label), ['repo', 'lib', 'README.md']);
    });

    test('a 1000-deep chain renders without recursion', () {
      const depth = 1000;
      final segments = [for (var i = 0; i < depth; i++) 'd$i'];
      final deep = DirectoryTree.fromPaths([
        '/${segments.first}/',
        '/${segments.join('/')}/leaf.txt',
      ]);
      final text = deep.render().split('\n');
      expect(text, hasLength(depth + 1));
      expect(text.first, 'd0/');
      expect(text[1], '└── d1/');
      expect(text.last, '${'    ' * (depth - 1)}└── leaf.txt');
      expect(
        deep.render(compactFolders: true),
        lines(['${segments.join('/')}/', '└── leaf.txt']),
      );
      expect(deep.render(maxDepth: 1), lines(['d0/', '└── d1/']));
    });
  });

  group('TreeStyle', () {
    test('presets have the documented connectors', () {
      expect(TreeStyle.unicode.branch, '├── ');
      expect(TreeStyle.unicode.lastBranch, '└── ');
      expect(TreeStyle.unicode.pipe, '│   ');
      expect(TreeStyle.unicode.gap, '    ');
      expect(TreeStyle.ascii.branch, '|-- ');
      expect(TreeStyle.ascii.lastBranch, '`-- ');
      expect(TreeStyle.ascii.pipe, '|   ');
      expect(TreeStyle.ascii.gap, '    ');
      for (final value in [
        TreeStyle.indent.branch,
        TreeStyle.indent.lastBranch,
        TreeStyle.indent.pipe,
        TreeStyle.indent.gap,
      ]) {
        expect(value, '  ');
      }
    });

    test('equality, hashCode, and toString', () {
      const copy = TreeStyle(
        branch: '├── ',
        lastBranch: '└── ',
        pipe: '│   ',
        gap: '    ',
      );
      expect(copy, TreeStyle.unicode);
      expect(copy.hashCode, TreeStyle.unicode.hashCode);
      expect(copy.toString(), 'TreeStyle.unicode');
      expect(TreeStyle.ascii.toString(), 'TreeStyle.ascii');
      expect(TreeStyle.indent.toString(), 'TreeStyle.indent');
      expect(TreeStyle.unicode == TreeStyle.ascii, isFalse);
      const custom = TreeStyle(
        branch: 'b',
        lastBranch: 'l',
        pipe: 'p',
        gap: 'g',
      );
      expect(
        custom.toString(),
        "TreeStyle(branch: 'b', lastBranch: 'l', pipe: 'p', gap: 'g')",
      );
      for (final different in const [
        TreeStyle(branch: 'x', lastBranch: 'l', pipe: 'p', gap: 'g'),
        TreeStyle(branch: 'b', lastBranch: 'x', pipe: 'p', gap: 'g'),
        TreeStyle(branch: 'b', lastBranch: 'l', pipe: 'x', gap: 'g'),
        TreeStyle(branch: 'b', lastBranch: 'l', pipe: 'p', gap: 'x'),
      ]) {
        expect(custom == different, isFalse, reason: '$different');
      }
    });
  });
}
