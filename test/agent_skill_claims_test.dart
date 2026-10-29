/// Every factual claim the AI plugin skills make, asserted against the API.
///
/// `tooling/ai/directory-tree/skills/` tells coding assistants what this
/// package does. Those files are excluded from the pub archive, so nothing
/// else in the build notices them going stale, and a wrong skill is worse
/// than a missing one: it makes an assistant confidently write broken code.
///
/// Two kinds of checks:
///
/// * every ```dart block of a skill appears below verbatim, inside a test
///   that runs it and compares each `print(...); // output` comment with
///   what it printed. Meta tests fail when a block has no copy here or its
///   prints go unchecked;
/// * every claim the prose makes (names, defaults, return values, thrown
///   errors) is asserted with `check`, grouped by skill section.
///
/// AGENTS.md requires skill facts to match the source. This is that rule,
/// enforced: when a claim here changes, update the skill in the same change.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/io.dart';
import 'package:test/test.dart';

const _skillsDir = 'tooling/ai/directory-tree/skills';
const _useSkill = '$_skillsDir/use-directory-tree/SKILL.md';
const _migrateSkill = '$_skillsDir/migrate-directory-tree-v1-to-v2/SKILL.md';

void main() {
  final blocks = _skillBlocks();

  /// The skill Dart block that contains [line].
  String block(String line) => blocks.singleWhere((b) => b.contains(line));

  group('meta', () {
    test('every skill Dart block is run by this file', () {
      final source = _normalize(
        File('test/agent_skill_claims_test.dart').readAsStringSync(),
      );
      expect(blocks, isNotEmpty);
      final missing = [
        for (final skillBlock in blocks)
          if (!source.contains(_normalize(skillBlock))) skillBlock,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'Copy these skill blocks into test/agent_skill_claims_test.dart:'
            '\n${missing.join('\n---\n')}',
      );
    });

    test('every skill print is compared with its output', () {
      final source = File(
        'test/agent_skill_claims_test.dart',
      ).readAsStringSync();
      final checked = {
        for (final match in RegExp(
          '_expectedPrints\\(block\\(([\'"])(.+?)\\1\\)\\)',
        ).allMatches(source))
          block(match.group(2)!),
      };
      for (final skillBlock in blocks) {
        final prints = skillBlock
            .split('\n')
            .where((line) => line.trimLeft().startsWith('print('))
            .toList();
        if (prints.isEmpty) continue;
        for (final line in prints) {
          expect(
            _printLine.hasMatch(line),
            isTrue,
            reason: 'Write skill prints as `print(...); // output`: $line',
          );
        }
        expect(
          checked.contains(skillBlock),
          isTrue,
          reason:
              'Compare the output of this block with '
              '_expectedPrints(block(...)):\n$skillBlock',
        );
      }
    });

    test('both skills exist and name the documented version', () {
      final version = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
      expect(version, '2.0.0', reason: 'update the skills for a new version');
      expect(File(_useSkill).readAsStringSync(), contains('2.0.0'));
      expect(File(_migrateSkill).readAsStringSync(), contains('2.0.0'));
    });
  });

  group('use-directory-tree blocks', () {
    test('building', () async {
      final printed = await _prints(() {
        final tree = DirectoryTree.fromPaths([
          '/repo/lib/src/tree.dart',
          '/repo/lib/main.dart',
          '/repo/assets/', // trailing separator: a directory entry
          '/repo/README.md',
        ]);
        print(tree.rootNodes.single.name); // repo
        print(tree.fileCount); // 3
        print(tree.nodeAt('/repo/assets')!.isExplicit); // true
        print(tree.nodeAt('/repo/lib')!.isExplicit); // false
      });
      expect(printed, _expectedPrints(block('/repo/assets/')));
    });

    test('rows and expansion', () async {
      final printed = await _prints(() {
        final tree = DirectoryTree.fromPaths([
          '/repo/lib/src/tree.dart',
          '/repo/lib/main.dart',
          '/repo/README.md',
        ]);
        var rows = tree.flatten(expansion: const ExpansionState.collapsed());
        print(rows.map((row) => row.label)); // (repo)
        rows = rows.toggleNode(rows.first.id); // the user clicked "repo"
        print(rows.map((row) => row.label)); // (repo, lib, README.md)
        final lib = tree.idOf('/repo/lib')!;
        final opened = rows.expandNode(lib);
        print(opened.length); // 5
        print(identical(opened.last, rows.last)); // true
        final saved = rows.requestedExpansion.toJson(); // persist this
        print(saved); // {default: collapsed, exceptions: [/repo]}
      });
      expect(printed, _expectedPrints(block('final opened = rows.expandNode')));
    });

    test('search and filters', () async {
      final printed = await _prints(() {
        final project = DirectoryTree.fromPaths([
          '/repo/lib/src/tree.dart',
          '/repo/lib/src/tree.g.dart',
          '/repo/test/tree_test.dart',
          '/repo/README.md',
        ]);
        List<String> find(String text) => project.nodes
            .where(TreeQuery.parse(text).matches)
            .map((node) => node.name)
            .toList();
        print(find('tree !*.g.dart')); // [tree.dart, tree_test.dart]
        print(find('ext:md')); // [README.md]
        print(find('type:dir path:lib')); // [lib, src]
        print(find('src/')); // [tree.dart, tree.g.dart]
        final ranges = TreeQuery.parse('TREE').matchRanges('tree_test.dart');
        print(ranges); // [(end: 4, start: 0)]
      });
      expect(printed, _expectedPrints(block("find('tree !*.g.dart')")));
    });

    test('selection and checkboxes', () async {
      final printed = await _prints(() {
        final tree = DirectoryTree.fromPaths([
          '/repo/lib/main.dart',
          '/repo/lib/util.dart',
          '/repo/README.md',
        ]);
        final lib = tree.idOf('/repo/lib')!;
        var checks = const SelectionState.empty(mode: SelectionMode.multiple);
        checks = checks.check(tree, lib);
        print(checks.checkStateOf(tree, lib)); // CheckState.checked
        final repo = tree.roots.single;
        print(checks.checkStateOf(tree, repo)); // CheckState.partial
        print(checks.isSelected(lib)); // false
        print(const SelectionState.empty().canCheck(tree, lib)); // false
      });
      expect(printed, _expectedPrints(block('checks.check(tree, lib)')));
    });

    test('diffs', () async {
      final printed = await _prints(() {
        final tree = DirectoryTree.fromPaths([
          '/repo/lib/src/tree.dart',
          '/repo/lib/main.dart',
          '/repo/README.md',
        ]);
        final before = tree.flatten();
        final after = before.collapseNode(tree.idOf('/repo/lib')!);
        final diff = ListDiff.compute(before, after, keyOf: (row) => row.id);
        print(diff.removedIndices); // [4, 3, 2]
        print(diff.insertedIndices); // []
        print(diff.changedIndices); // [1]
      });
      expect(printed, _expectedPrints(block('print(diff.removedIndices)')));
    });

    test('scanning the file system', () async {
      final temp = Directory.systemTemp.createTempSync('skill_scan_');
      addTearDown(() => temp.deleteSync(recursive: true));
      Directory('${temp.path}/lib/src').createSync(recursive: true);
      Directory('${temp.path}/build/out').createSync(recursive: true);
      File('${temp.path}/lib/main.dart').writeAsStringSync('');
      final projectPath = temp.path;

      final printed = await _prints(() async {
        // import 'package:directory_tree/io.dart'; as well as the core library
        final scanner = DirectoryScanner(
          maxDepth: 2,
          skip: (entity) => entity.path.endsWith('build'),
          onError: (error) => print('skipped ${error.path}'),
        );
        final scanned = await scanner.scanTree(projectPath);
        print(scanned.rootNodes.length); // 1
      });
      expect(printed, _expectedPrints(block('scanner.scanTree(projectPath)')));
    });
  });

  group('migrate-directory-tree-v1-to-v2 blocks', () {
    test('a typical rewrite', () async {
      final printed = await _prints(() {
        final tree = DirectoryTree.fromPaths([
          r'C:\Repo\lib\main.dart',
          r'c:\repo\README.md',
        ], options: const TreeOptions(paths: PathPolicy.caseInsensitive));
        print(tree.roots.single.value); // c:/repo
        var expansion = const ExpansionState.collapsed(); // was ExpansionSet()
        expansion = expansion.expand(tree.roots.single); // assign the result
        final rows = tree.flatten(expansion: expansion);
        print(rows.map((row) => row.label)); // (Repo, lib, README.md)
        final diff = ListDiff.compute(rows, tree.flatten(), keyOf: (r) => r.id);
        print(diff.insertedIndices); // [2]
      });
      expect(printed, _expectedPrints(block('was ExpansionSet()')));
    });
  });

  test('use-directory-tree prose claims match the shipped API', () async {
    final failures = <String>[];
    void check(String claim, Object? actual, Object? expected) {
      if (actual.toString() == expected.toString()) return;
      failures.add(
        '$claim\n    skill says: $expected\n    actual    : $actual',
      );
    }

    final tree = DirectoryTree.fromPaths([
      '/repo/lib/src/tree.dart',
      '/repo/lib/main.dart',
      '/repo/README.md',
    ]);
    final repo = tree.roots.single;
    final lib = tree.idOf('/repo/lib')!;
    final src = tree.idOf('/repo/lib/src')!;
    final mainDart = tree.idOf('/repo/lib/main.dart')!;
    final readme = tree.idOf('/repo/README.md')!;
    const missing = NodeId('/repo/gone');

    // Exact names.
    check(
      'fromPaths returns DirectoryTree<Object?>',
      _staticType(DirectoryTree.fromPaths(const [])),
      _type<DirectoryTree<Object?>>(),
    );
    check(
      'flatten returns TreeRows<T>, a List<TreeRow<T>>',
      [_staticType(tree.flatten()), _isRowList(tree.flatten())],
      [_type<TreeRows<Object?>>(), true],
    );
    check(
      'rows.expand is Iterable.expand, not a folder expansion',
      tree
          .flatten(expansion: const ExpansionState.collapsed())
          .expand((row) => [row, row])
          .length,
      2,
    );
    check('tree[id] looks up by id', tree[lib]?.name, 'lib');
    check(
      'ancestorsOf is nearest first and excludes the node',
      tree.ancestorsOf(mainDart).map((n) => n.name),
      '(lib, repo)',
    );
    check(
      'TreeEntry.path is the raw path',
      const TreeEntry<Object?>.file(r'C:\a.txt').path,
      r'C:\a.txt',
    );
    check('node.kind is TreeNodeKind', tree[lib]!.kind, TreeNodeKind.directory);

    // Building.
    check(
      'a trailing backslash makes a directory entry',
      DirectoryTree.fromPaths([r'C:\r\empty\']).nodeAt('C:/r/empty')?.isFile,
      false,
    );
    check(
      'a trailing backslash is a character when it is not a separator',
      DirectoryTree.fromPaths(
        [r'/r/x\'],
        options: const TreeOptions(
          paths: PathPolicy(backslashIsSeparator: false),
        ),
      ).files.single.name,
      r'x\',
    );
    final docs = DirectoryTree.fromPaths(['/r/docs/a.md', '/r/b.txt']);
    check(
      'an inferred directory disappears with its last file',
      docs.rebuild((b) => b.remove('/r/docs/a.md')).nodeAt('/r/docs'),
      null,
    );
    check(
      'a directory entry keeps it',
      docs
          .rebuild(
            (b) => b
              ..addDirectory('/r/docs')
              ..remove('/r/docs/a.md'),
          )
          .nodeAt('/r/docs')
          ?.isDirectory,
      true,
    );
    check('an inferred directory has no entry', tree[lib]!.entry, null);
    final merged = DirectoryTree<int>.build([
      const TreeEntry.file('/r/a.txt', data: 1),
      const TreeEntry.file('/r/b.txt', data: 2),
      const TreeEntry.file('/r/a.txt', data: 3),
    ]);
    check(
      'duplicates merge: the later wins at the first position',
      merged.entries.map((e) => e.data),
      '(3, 2)',
    );
    check(
      'building never throws on bad input',
      DirectoryTree.fromPaths(['', '../x', '/r/a']).issues.length,
      2,
    );
    final rebuilt = tree.rebuild((b) => b.addFile('/repo/lib/new.dart'));
    check('rebuild keeps unchanged ids', rebuilt[lib]?.id, lib);
    check(
      'rebuild leaves the original tree',
      tree.contains(rebuilt.idOf('/repo/lib/new.dart')!),
      false,
    );
    final builder = DirectoryTreeBuilder<Object?>(entries: tree.entries);
    check('remove is recursive by default', builder.remove('/repo/lib'), 2);
    final shallow = DirectoryTreeBuilder<Object?>()
      ..addDirectory('/r/d')
      ..addFile('/r/d/a.txt');
    check(
      'remove(recursive: false) removes only that entry',
      shallow.remove('/r/d', recursive: false),
      1,
    );
    check(
      'DirectoryTree.empty() has no nodes',
      DirectoryTree<int>.empty().length,
      0,
    );
    check(
      'DirectoryTree.empty keeps fixed roots',
      DirectoryTree<int>.empty(
        options: const TreeOptions(roots: TreeRoots.fixed(['/w'])),
      ).length,
      1,
    );
    check(
      'data takes part in ==',
      DirectoryTree<int>.build([const TreeEntry.file('/r/a', data: 1)]) ==
          DirectoryTree<int>.build([const TreeEntry.file('/r/a', data: 2)]),
      false,
    );

    // Nodes, ids, and lookups.
    check('switch over TreeNode is exhaustive', _kindName(tree[lib]!), 'dir');
    check('FileNode', tree[mainDart] is FileNode<Object?>, true);
    check('DirectoryNode.children are ids', tree[lib] is DirectoryNode, true);
    check(
      'DirectoryNode.children holds NodeIds',
      (tree[lib]! as DirectoryNode<Object?>).children,
      [src, mainDart],
    );
    check('top-level parent is null', tree[repo]!.parent, null);
    check('top-level depth is 0', tree[repo]!.depth, 0);
    check('isRoot means top level', tree[repo]!.isRoot, true);
    check(
      'a top-level node is not a path root',
      tree[repo]!.path.isRoot,
      false,
    );
    check('NodeId.value', lib.value, '/repo/lib');
    check('NodeId(saved) restores', NodeId(lib.value) == lib, true);
    final folded = DirectoryTree.fromPaths([
      '/Repo/README.md',
    ], options: const TreeOptions(paths: PathPolicy.caseInsensitive));
    check(
      'case-insensitive ids are lowercased',
      folded.idOf('/Repo/README.md')!.value,
      '/repo/readme.md',
    );
    check(
      'a hand-built id misses under a case-insensitive policy',
      folded[const NodeId('/Repo/README.md')],
      null,
    );
    check(
      'idOf works for absent nodes',
      tree.idOf('/nope/x')?.value,
      '/nope/x',
    );
    check('idOf is null only when unparseable', tree.idOf(''), null);
    check('nodeAt returns null when absent', tree.nodeAt('/nope'), null);
    check('unknown id lookup', tree[missing], null);
    check('unknown indexOf', tree.indexOf(missing), -1);
    check('unknown subtreeSizeOf', tree.subtreeSizeOf(missing), 0);
    check('unknown contains', tree.contains(missing), false);
    check('unknown childrenOf', tree.childrenOf(missing).isEmpty, true);
    check('unknown parentOf', tree.parentOf(missing), null);
    check('unknown rootOf', tree.rootOf(missing), null);
    check('unknown ancestorsOf', tree.ancestorsOf(missing).isEmpty, true);
    check('unknown descendantsOf', tree.descendantsOf(missing).isEmpty, true);
    check('isAncestor is strict', tree.isAncestor(lib, lib), false);
    check('isAncestor', tree.isAncestor(repo, mainDart), true);
    check(
      'a subtree is a slice of nodes',
      tree.nodes
          .sublist(
            tree.indexOf(lib),
            tree.indexOf(lib) + tree.subtreeSizeOf(lib),
          )
          .map((n) => n.name),
      '(lib, src, tree.dart, main.dart)',
    );
    check(
      'counts',
      [tree.length, tree.fileCount, tree.directoryCount],
      [6, 3, 3],
    );
    check(
      'nodes is unmodifiable',
      _throws<UnsupportedError>(() => tree.nodes.add(tree.nodes.first)),
      true,
    );

    // Paths and PathPolicy.
    check(
      'C:\\work\\..\\repo\\',
      TreePath.parse(r'C:\work\..\repo\'),
      'C:/repo',
    );
    check(
      'a relative path climbing above its start throws',
      _throws<FormatException>(() => TreePath.parse('../x')),
      true,
    );
    check('tryParse returns null', TreePath.tryParse('../x'), null);
    check(
      'an empty path throws',
      _throws<FormatException>(() => TreePath.parse('')),
      true,
    );
    check(
      'a NUL character throws',
      _throws<FormatException>(() => TreePath.parse('a\u0000b')),
      true,
    );
    check('relative root', TreePath.parse('a/b').root, '');
    check('relative root name', TreePath.parse('a').parent!.name, '.');
    check('POSIX root', TreePath.parse('/a').root, '/');
    check('drive root', TreePath.parse(r'c:\a').root, 'C:/');
    check('drive root name', TreePath.parse('C:/').name, 'C:');
    check(
      'UNC root',
      TreePath.parse(r'\\server\share\a').root,
      '//server/share/',
    );
    check(
      'extension is the last one',
      TreePath.parse('/a/x.tar.gz').extension,
      '.gz',
    );
    check('extension of .env', TreePath.parse('/a/.env').extension, '');
    check(
      'extension keeps case',
      TreePath.parse('/a/IMG.JPG').extension,
      '.JPG',
    );
    check('child', TreePath.parse('/a').child('b'), '/a/b');
    check(
      'isWithin',
      TreePath.parse('/a/b').isWithin(TreePath.parse('/a')),
      true,
    );
    check(
      'relativeTo',
      TreePath.parse('/a/b/c').relativeTo(TreePath.parse('/a')),
      'b/c',
    );
    check('isAbsolute', TreePath.parse('a/b').isAbsolute, false);
    const policy = PathPolicy();
    check(
      'PathPolicy defaults',
      [
        policy.caseSensitive,
        policy.backslashIsSeparator,
        policy.unicodeNormalizer,
      ],
      [true, true, null],
    );
    check(
      'PathPolicy.caseInsensitive',
      PathPolicy.caseInsensitive.caseSensitive,
      false,
    );
    final twoSpellings = ['/Repo/README.md', '/repo/readme.md'];
    check(
      'the default policy keeps both spellings',
      DirectoryTree.fromPaths(twoSpellings).fileCount,
      2,
    );
    final mergedCase = DirectoryTree.fromPaths(
      twoSpellings,
      options: const TreeOptions(paths: PathPolicy.caseInsensitive),
    );
    check('case-insensitive merges', mergedCase.fileCount, 1);
    check(
      'case-insensitive keeps a display spelling',
      mergedCase.files.single.path,
      '/repo/readme.md',
    );
    check(
      'the same normalizer object keeps policies equal',
      const PathPolicy(unicodeNormalizer: _identity) ==
          const PathPolicy(unicodeNormalizer: _identity),
      true,
    );
    check(
      'different normalizer objects make policies unequal',
      PathPolicy(unicodeNormalizer: (p) => p) ==
          PathPolicy(unicodeNormalizer: (p) => p),
      false,
    );

    // Options: roots and order.
    const defaults = TreeOptions();
    check(
      'TreeOptions defaults',
      [
        defaults.paths,
        defaults.roots,
        defaults.order == TreeOrder.directoriesFirst,
      ],
      [const PathPolicy(), const TreeRoots.minimal(), true],
    );
    final split = DirectoryTree.fromPaths([
      '/ws/a/src/x.dart',
      '/ws/b/src/y.dart',
    ]);
    check(
      'minimal roots and collision labels',
      split.rootNodes.map((n) => n.label),
      '(a/src, b/src)',
    );
    check('names stay src', split.rootNodes.map((n) => n.name), '(src, src)');
    check(
      'commonAncestor',
      DirectoryTree.fromPaths(
        ['/ws/a/src/x.dart', '/ws/b/src/y.dart'],
        options: const TreeOptions(roots: TreeRoots.commonAncestor()),
      ).rootNodes.single.path,
      '/ws',
    );
    final fixed = DirectoryTree.fromPaths([
      '/w/a.txt',
      '/x/b.txt',
      '/e',
    ], options: const TreeOptions(roots: TreeRoots.fixed(['/w', '/e'])));
    check(
      'fixed roots exist when empty',
      fixed.rootNodes.map((n) => n.path),
      '(/e, /w)',
    );
    check(
      'outside fixed roots is outsideRoots; a file equal to a root conflicts',
      fixed.issues.map((i) => i.kind),
      '(TreeIssueKind.outsideRoots, TreeIssueKind.conflict)',
    );
    check(
      'filesystem roots',
      DirectoryTree.fromPaths(
        ['/r/a.txt', r'C:\b.txt'],
        options: const TreeOptions(roots: TreeRoots.filesystem()),
      ).rootNodes.map((n) => n.name),
      '(/, C:)',
    );
    check(
      'compareNames is natural',
      TreeOrder.compareNames('file2', 'file10') < 0,
      true,
    );
    check(
      'compareNames ignores case first',
      TreeOrder.compareNames('alpha', 'Beta') < 0,
      true,
    );
    check(
      'compareNames falls back to code units',
      TreeOrder.compareNames('A', 'a') < 0,
      true,
    );
    final mixed = ['/d/b/', '/d/a.txt'];
    check(
      'directoriesFirst',
      DirectoryTree.fromPaths(mixed).nodes.skip(1).map((n) => n.name),
      '(b, a.txt)',
    );
    check(
      'alphabetical',
      DirectoryTree.fromPaths(
        mixed,
        options: const TreeOptions(order: TreeOrder.alphabetical),
      ).nodes.skip(1).map((n) => n.name),
      '(a.txt, b)',
    );
    check(
      'ties break by id',
      DirectoryTree.fromPaths([
        '/d/b.txt',
        '/d/a.txt',
        '/d/c.txt',
      ], options: TreeOptions(order: (a, b) => 0)).files.map((n) => n.name),
      '(a.txt, b.txt, c.txt)',
    );
    check(
      'every TreeOrder.by call is a new function',
      TreeOptions(order: TreeOrder.by<int>((a, b) => 0)) ==
          TreeOptions(order: TreeOrder.by<int>((a, b) => 0)),
      false,
    );
    final stored = TreeOrder.by<int>((a, b) => 0);
    check(
      'a stored comparator keeps options equal',
      TreeOptions(order: stored) == TreeOptions(order: stored),
      true,
    );

    // Minimal roots move when entries change.
    const moving = ['/repo/lib/a.dart', '/repo/README.md'];
    check(
      'removing README.md makes lib the minimal root',
      DirectoryTree.fromPaths(
        moving,
      ).rebuild((b) => b.remove('/repo/README.md')).rootNodes.single.path,
      '/repo/lib',
    );
    check(
      'a directory entry keeps the root',
      DirectoryTree.fromPaths([
        '/repo/',
        ...moving,
      ]).rebuild((b) => b.remove('/repo/README.md')).rootNodes.single.path,
      '/repo',
    );
    check(
      'a fixed root keeps the root',
      DirectoryTree.fromPaths(
        moving,
        options: const TreeOptions(roots: TreeRoots.fixed(['/repo'])),
      ).rebuild((b) => b.remove('/repo/README.md')).rootNodes.single.path,
      '/repo',
    );

    // Issues.
    final checked = DirectoryTree.fromPaths([
      '',
      '../up.txt',
      '/r/a.txt',
      '/r/a.txt/b.txt',
    ], options: const TreeOptions(roots: TreeRoots.fixed(['../bad', '/r'])));
    check(
      'issue kinds in input order, fixed-root issues first',
      checked.issues.map((i) => i.kind.name),
      '(invalidPath, invalidPath, invalidPath, conflict)',
    );
    check('a bad fixed root has no entry', checked.issues.first.entry, null);
    check('issue path is raw', checked.issues.first.path, '../bad');
    check(
      'a file entry at a path root is invalid',
      DirectoryTree.build([
        const TreeEntry<Object?>.file('/'),
      ]).issues.single.kind,
      TreeIssueKind.invalidPath,
    );

    // Rows and expansion.
    final all = tree.flatten();
    check(
      'flatten expands everything by default',
      all.map((r) => r.label),
      '(repo, lib, src, tree.dart, main.dart, README.md)',
    );
    check(
      'TreeRows is unmodifiable',
      [
        _throws<UnsupportedError>(() => all.add(all.first)),
        _throws<UnsupportedError>(() => all.removeAt(0)),
        _throws<UnsupportedError>(all.sort),
      ],
      [true, true, true],
    );
    final row = all[1];
    check(
      'TreeRow fields',
      [row.id, row.node.name, row.depth, row.label, row.isExpanded],
      [lib, 'lib', 1, 'lib', true],
    );
    check(
      'TreeRow flags',
      [row.hasChildren, row.isLast, row.guides, row.isMatch, row.chain.length],
      [
        true,
        false,
        [false],
        true,
        1,
      ],
    );
    check(
      'unknown ids return the same rows',
      identical(all.toggleNode(missing), all),
      true,
    );
    check(
      'files return the same rows',
      identical(all.expandNode(readme), all),
      true,
    );
    final collapsedSrc = all.collapseNode(src);
    final restored = collapsedSrc.collapseNode(lib).expandNode(lib);
    check(
      'collapsing keeps the state of folders below',
      restored.map((r) => r.label),
      '(repo, lib, src, main.dart, README.md)',
    );
    final closed = tree.flatten(expansion: const ExpansionState.collapsed());
    check('indexOfNode is -1 when hidden', closed.indexOfNode(lib), -1);
    check('rowOf is null when hidden', closed.rowOf(lib), null);
    final srcIndex = all.indexOfNode(src);
    check('parentIndexOf', all[all.parentIndexOf(srcIndex)!].label, 'lib');
    check(
      'firstChildIndexOf',
      all[all.firstChildIndexOf(srcIndex)!].label,
      'tree.dart',
    );
    check(
      'firstChildIndexOf of a file',
      all.firstChildIndexOf(all.length - 1),
      null,
    );
    check('parentIndexOf of depth 0', all.parentIndexOf(0), null);
    var calls = 0;
    final counting = TreeFilter.where<Object?>((node) {
      calls++;
      return node.name == 'main.dart';
    });
    final searched = tree.flatten(
      expansion: const ExpansionState.collapsed(),
      filter: counting,
    );
    check('flatten calls the filter once per node', calls, tree.length);
    final reapplied = searched.withExpansion(const ExpansionState.collapsed());
    check('withExpansion never calls the filter', calls, tree.length);
    check(
      'withExpansion without revealMatches uses the state as given',
      reapplied.map((r) => r.label),
      '(repo)',
    );
    check(
      'updates never call the filter',
      [searched.toggleNode(lib).reveal(src).length, calls],
      [2, tree.length],
    );
    check(
      'expansion includes revealed folders',
      searched.expansion.toJson(),
      '{default: collapsed, exceptions: [/repo, /repo/lib]}',
    );
    check(
      'requestedExpansion excludes them',
      searched.requestedExpansion.toJson(),
      '{default: collapsed, exceptions: []}',
    );
    check(
      'fromJson round-trips',
      ExpansionState.fromJson(searched.expansion.toJson()) ==
          searched.expansion,
      true,
    );
    check(
      'prune drops files and unknown ids',
      const ExpansionState.collapsed()
          .expandAll([lib, readme, missing])
          .prune(tree)
          .exceptions,
      {lib},
    );
    final state = ExpansionState.withExpanded([repo, lib]);
    check(
      'collapseAll collapses only the given ids',
      state.collapseAll([lib]).isExpanded(repo),
      true,
    );
    check(
      'reveal expands the ancestors, not the node',
      const ExpansionState.collapsed().reveal(tree, src).toJson(),
      '{default: collapsed, exceptions: [/repo, /repo/lib]}',
    );
    check(
      'expandSubtree',
      const ExpansionState.collapsed().expandSubtree(tree, lib).toJson(),
      '{default: collapsed, exceptions: [/repo/lib, /repo/lib/src]}',
    );
    check(
      'collapseSubtree',
      const ExpansionState.expanded().collapseSubtree(tree, lib).toJson(),
      '{default: expanded, exceptions: [/repo/lib, /repo/lib/src]}',
    );
    check(
      'setExpanded',
      const ExpansionState.collapsed()
          .setExpanded(lib, expanded: true)
          .isExpanded(lib),
      true,
    );
    check(
      'withCollapsed',
      [
        ExpansionState.withCollapsed([lib]).expandsByDefault,
        ExpansionState.withCollapsed([lib]).isExpanded(lib),
      ],
      [true, false],
    );
    const unchanged = ExpansionState.collapsed();
    check(
      'no-op returns the same state',
      identical(unchanged.collapse(lib), unchanged),
      true,
    );
    final compact = DirectoryTree.fromPaths([
      '/w/app/lib/src/main.dart',
      '/w/README.md',
    ]).flatten(compactFolders: true);
    check(
      'compactFolders',
      compact.map((r) => r.label),
      '(w, app/lib/src, main.dart, README.md)',
    );
    check(
      'a compacted row is its deepest directory',
      compact[1].node.name,
      'src',
    );
    final hiddenRoots = tree.flatten(showRoots: false);
    check(
      'showRoots: false makes the children depth 0',
      hiddenRoots.where((r) => r.depth == 0).map((r) => r.label),
      '(lib, README.md)',
    );
    check('a hidden root has no row', hiddenRoots.indexOfNode(repo), -1);
    check(
      'expandNode and collapseNode ignore hidden roots',
      [
        identical(hiddenRoots.collapseNode(repo), hiddenRoots),
        identical(hiddenRoots.toggleNode(repo), hiddenRoots),
      ],
      [true, true],
    );

    // Search and filters.
    final project = DirectoryTree.fromPaths([
      '/repo/lib/src/tree.dart',
      '/repo/lib/main.dart',
      '/repo/docs/my notes.md',
      '/repo/docs/a*b.txt',
      '/repo/dist/app.tar.gz',
      '/repo/x.dart/',
      '/repo/test_1.md',
      '/repo/IMG.JPG',
    ]);
    List<String> find(String text, {bool caseSensitive = false}) {
      final query = TreeQuery.parse(text, caseSensitive: caseSensitive);
      return project.nodes.where(query.matches).map((n) => n.name).toList();
    }

    check('plain term', find('main'), '[main.dart]');
    check('every term must match', find('tree dart'), '[tree.dart]');
    check('quoted phrase', find('"my notes"'), '[my notes.md]');
    check('quoted text is literal', find('"a*b"'), '[a*b.txt]');
    check('negation', find('ext:md !notes'), '[test_1.md]');
    check(
      'glob matches the whole name',
      find('*.md'),
      '[my notes.md, test_1.md]',
    );
    check('? is one character', find('test_?.md'), '[test_1.md]');
    check('ext: is a suffix test', find('ext:tar.gz'), '[app.tar.gz]');
    check('ext: lists', find('ext:gz,JPG'), '[app.tar.gz, IMG.JPG]');
    check(
      'directories never match ext:',
      find('ext:dart'),
      '[tree.dart, main.dart]',
    );
    check(
      'type: aliases',
      [find('type:f').length, find('type:file').length],
      [7, 7],
    );
    check(
      'type:dir aliases',
      [
        find('type:d'),
        find('type:directory'),
        find('type:dir'),
      ].map((l) => l.length),
      '(6, 6, 6)',
    );
    check('path:', find('path:lib/src'), '[src, tree.dart]');
    check('lib/src', find('lib/src'), '[src]');
    check('lib/', find('lib/'), '[src, main.dart]');
    check('src/*.dart', find('src/*.dart'), '[tree.dart]');
    check('plain terms look at the name only', find('repo'), '[repo]');
    check(
      'ext: and type: ignore case when caseSensitive',
      find('ext:jpg TYPE:FILE', caseSensitive: true),
      '[IMG.JPG]',
    );
    check(
      'caseSensitive applies to names',
      find('MAIN', caseSensitive: true),
      '[]',
    );
    check(
      'parse never throws',
      [
        '"',
        '!',
        'ext:',
        'type:x',
        '**',
        r'\',
        'path:',
      ].map(TreeQuery.parse).length,
      7,
    );
    check('unknown key is literal', find('foo:bar'), '[]');
    check('empty query matchesAll', TreeQuery.parse('  ').matchesAll, true);
    check(
      '* does not report matchesAll',
      TreeQuery.parse('*').matchesAll,
      false,
    );
    check(
      'flatten skips a matchesAll filter',
      tree.flatten(filter: TreeQuery.parse('')).filter,
      null,
    );
    check(
      'matchRanges skips globs, keys, and negations',
      TreeQuery.parse('*.dart ext:dart !main tree').matchRanges('tree.dart'),
      '[(end: 4, start: 0)]',
    );
    check(
      'matchRanges merges overlaps',
      TreeQuery.parse('tre ree').matchRanges('tree'),
      '[(end: 4, start: 0)]',
    );
    check(
      'TreeFilter.where<int> never matches an Object? tree',
      tree.nodes.any(TreeFilter.where<int>((n) => true).matches),
      false,
    );
    check(
      'TreeFilter.where<Object?> matches',
      tree.nodes.every(TreeFilter.where<Object?>((n) => true).matches),
      true,
    );
    check('TreeFilter.all', TreeFilter.all.matchesAll, true);
    check(
      'combinators',
      tree.nodes
          .where(
            TreeFilter.where<Object?>((n) => n.isFile)
                .and(TreeQuery.parse('main').negate())
                .or(TreeQuery.parse('type:dir lib'))
                .matches,
          )
          .map((n) => n.name),
      '(lib, tree.dart, README.md)',
    );
    check(
      'isMatch is true without a filter',
      all.every((r) => r.isMatch),
      true,
    );
    final mdSearch = tree.flatten(filter: TreeQuery.parse('main'));
    check(
      'a filtered view keeps ancestors, isMatch tells them apart',
      mdSearch.map((r) => '${r.label}:${r.isMatch}'),
      '(repo:false, lib:false, main.dart:true)',
    );
    check(
      'expandMatches: false keeps matches hidden',
      tree
          .flatten(
            expansion: const ExpansionState.collapsed(),
            filter: TreeQuery.parse('main'),
            expandMatches: false,
          )
          .map((r) => r.label),
      '(repo)',
    );
    check(
      'a filter that matches nothing gives empty rows',
      tree.flatten(filter: TreeQuery.parse('zzz')).isEmpty,
      true,
    );
    check(
      'hasChildren is false when the filter hides every child',
      tree.flatten(filter: TreeQuery.parse('type:dir')).rowOf(src)!.hasChildren,
      false,
    );

    // Selection and checkboxes.
    const empty = SelectionState.empty();
    check('empty defaults to single mode', empty.mode, SelectionMode.single);
    final selected = empty.select(lib);
    check('select sets the anchor', selected.anchor, lib);
    check(
      'single toggle of the selected id clears',
      selected.toggle(lib).isEmpty,
      true,
    );
    final order = all.map((r) => r.id);
    final ranged = const SelectionState.empty(
      mode: SelectionMode.multiple,
    ).select(lib).extendTo(mainDart, order);
    check(
      'extendTo selects in display order and keeps the anchor',
      [ranged.selected.map((id) => id.value).toList(), ranged.anchor],
      [
        [
          '/repo/lib',
          '/repo/lib/src',
          '/repo/lib/src/tree.dart',
          '/repo/lib/main.dart',
        ],
        lib,
      ],
    );
    final picked = const SelectionState.empty(
      mode: SelectionMode.multiple,
    ).check(tree, lib);
    check('check selects leaves, not the directory', picked.selected, {
      tree.idOf('/repo/lib/src/tree.dart'),
      mainDart,
    });
    check('uncheck', picked.uncheck(tree, lib).isEmpty, true);
    check(
      'toggleCheck on a partial directory checks it',
      picked.toggleCheck(tree, repo).checkStateOf(tree, repo),
      CheckState.checked,
    );
    check(
      'toggleCheck on a checked node unchecks it',
      picked.toggleCheck(tree, lib).checkStateOf(tree, lib),
      CheckState.unchecked,
    );
    check(
      'toggleCheck on an unchecked node checks it',
      const SelectionState.empty(
        mode: SelectionMode.multiple,
      ).toggleCheck(tree, lib).checkStateOf(tree, lib),
      CheckState.checked,
    );
    check(
      'single-mode toggleCheck of several leaves throws StateError',
      _throws<StateError>(
        () => const SelectionState.empty().toggleCheck(tree, lib),
      ),
      true,
    );
    check(
      'checkStates covers every node',
      picked.checkStates(tree).length,
      tree.length,
    );
    check(
      'empty directories are leaves',
      const SelectionState.empty(mode: SelectionMode.multiple)
          .check(tree, mainDart)
          .check(tree, src)
          .checkStateOf(
            tree.rebuild((b) => b.addDirectory('/repo/lib/empty')),
            lib,
          ),
      CheckState.partial,
    );
    check(
      'single-mode check of several leaves throws StateError',
      _throws<StateError>(() => empty.check(tree, lib)),
      true,
    );
    check('single-mode canCheck of one leaf', empty.canCheck(tree, src), true);
    check(
      'canCheck is false for unknown ids',
      empty.canCheck(tree, missing),
      false,
    );
    check(
      'single mode with two ids throws ArgumentError',
      _throws<ArgumentError>(() => SelectionState(selected: [lib, src])),
      true,
    );
    check(
      'SelectionState JSON round-trips',
      SelectionState.fromJson(ranged.toJson()) == ranged,
      true,
    );
    check(
      'a no-op returns the same object',
      identical(ranged.addAll(const []), ranged),
      true,
    );
    check(
      'withMode(single) keeps the selected anchor',
      ranged.withMode(SelectionMode.single).selected,
      {lib},
    );
    check(
      'prune drops unknown ids',
      SelectionState(
        mode: SelectionMode.multiple,
        selected: [lib, missing],
      ).prune(tree).selected,
      {lib},
    );

    // Diffs.
    final before = ['a', 'b', 'c', 'd'];
    final after = ['b', 'x', 'a', 'd'];
    final moves = ListDiff.compute(before, after, keyOf: (item) => item);
    final applied = [...before];
    for (final index in moves.removedIndices) {
      applied.removeAt(index);
    }
    for (final index in moves.insertedIndices) {
      applied.insert(index, after[index]);
    }
    check('removals then insertions give the new list', applied, after);
    check(
      'a move is one removal plus one insertion',
      moves,
      'ListDiff(removed: [2, 0], inserted: [1, 2], changed: [])',
    );
    check(
      'isEmpty requires all three lists empty',
      ListDiff.compute(
        [1],
        [1],
        keyOf: (v) => 'k',
        equals: (a, b) => false,
      ).isEmpty,
      false,
    );
    check(
      'a duplicate key in the middle region throws ArgumentError',
      _throws<ArgumentError>(
        () => ListDiff.compute(['a', 'x', 'a'], ['b'], keyOf: (v) => v),
      ),
      true,
    );
    final rescanned = tree.rebuild(
      (b) => b
        ..addFile('/repo/lib/src/rows.dart')
        ..remove('/repo/lib/main.dart'),
    );
    final treeDiff = TreeDiff.compute(tree, rescanned);
    check(
      'TreeDiff added and removed',
      [treeDiff.added, treeDiff.removed],
      [
        [tree.idOf('/repo/lib/src/rows.dart')],
        [mainDart],
      ],
    );
    check(
      'TreeDiff ignores sibling order',
      TreeDiff.compute(
        DirectoryTree.fromPaths(mixed),
        DirectoryTree.fromPaths(
          mixed,
          options: const TreeOptions(order: TreeOrder.alphabetical),
        ),
      ).isEmpty,
      true,
    );
    check(
      'TreeDiff reports changed data',
      TreeDiff.compute(
        DirectoryTree<int>.build([const TreeEntry.file('/r/a', data: 1)]),
        DirectoryTree<int>.build([const TreeEntry.file('/r/a', data: 2)]),
      ).changed,
      [const NodeId('/r/a')],
    );
    check(
      'TreeDiff needs the same PathPolicy',
      TreeDiff.compute(
        DirectoryTree.fromPaths(['/R/a']),
        DirectoryTree.fromPaths([
          '/R/a',
        ], options: const TreeOptions(paths: PathPolicy.caseInsensitive)),
      ).added.length,
      2,
    );

    // Rendering text.
    final text = tree.render();
    check('render has no trailing newline', text.endsWith('\n'), false);
    check(
      'render of an empty tree',
      DirectoryTree.fromPaths(const []).render(),
      '',
    );
    check('directories get a trailing /', text.split('\n').first, 'repo/');
    check(
      'a custom label replaces the default text',
      tree.render(label: (r) => r.label).split('\n').first,
      'repo',
    );
    check('maxDepth: 0', tree.render(maxDepth: 0), 'repo/');
    check('a negative maxDepth prints nothing', tree.render(maxDepth: -1), '');
    check(
      'styles',
      [
        TreeStyle.unicode.branch,
        TreeStyle.ascii.branch,
        TreeStyle.indent.branch,
      ],
      ['├── ', '|-- ', '  '],
    );
    check(
      'render reveals filter matches',
      tree.render(
        expansion: const ExpansionState.collapsed(),
        filter: TreeQuery.parse('main'),
      ),
      'repo/\n└── lib/\n    └── main.dart',
    );

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('use-directory-tree scanner claims match the shipped API', () async {
    final temp = Directory.systemTemp.createTempSync('skill_scanner_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final root = temp.path;
    final sep = Platform.pathSeparator;
    Directory('$root${sep}a${sep}b${sep}c').createSync(recursive: true);
    Directory('$root$sep.hidden').createSync();
    Directory('$root${sep}skipped${sep}deep').createSync(recursive: true);
    File('$root${sep}a${sep}file.txt').writeAsStringSync('');
    File('$root$sep.env').writeAsStringSync('');

    const scanner = DirectoryScanner();
    expect(scanner.includeHidden, isFalse);
    expect(scanner.followLinks, isFalse);
    expect(scanner.maxDepth, isNull);

    final entries = await scanner.scan(root);
    expect(entries, isA<List<TreeEntry<FileSystemEntity>>>());
    expect(entries.first.path, root, reason: 'the root is included');
    expect(entries.first.isDirectory, isTrue);
    expect(
      entries.map((e) => e.path).toList(),
      [...entries.map((e) => e.path)]..sort(),
      reason: 'entries are sorted by path',
    );
    expect(
      entries.any((e) => e.path.contains('.hidden') || e.path.contains('.env')),
      isFalse,
      reason: 'hidden entries are skipped by default',
    );
    final file = entries.singleWhere((e) => e.path.endsWith('file.txt'));
    expect(file.data, isA<File>());
    String describe(TreeEntry<FileSystemEntity> e) =>
        '${e.kind.name} ${e.path} ${e.data.runtimeType}';
    expect(
      scanner.scanSync(root).map(describe),
      entries.map(describe),
      reason: 'scanSync returns the same entries as scan',
    );

    final depth0 = await const DirectoryScanner(maxDepth: 0).scan(root);
    expect(depth0.map((e) => e.path), [root]);
    final depth1 = await const DirectoryScanner(maxDepth: 1).scan(root);
    expect(
      depth1.map((e) => e.path).where((p) => p.contains('${sep}b')),
      isEmpty,
      reason: 'directories at the limit are reported but not listed',
    );
    expect(depth1.any((e) => e.path == '$root${sep}a'), isTrue);

    final seen = <String>[];
    final skipped = await DirectoryScanner(
      skip: (entity) {
        seen.add(entity.path);
        return entity.path.endsWith('skipped');
      },
    ).scan(root);
    expect(skipped.any((e) => e.path.contains('skipped')), isFalse);
    expect(
      seen.any((p) => p.endsWith('deep')),
      isFalse,
      reason: 'skip prunes the subtree without listing it',
    );

    final tree = await scanner.scanTree(root);
    expect(tree, isA<DirectoryTree<FileSystemEntity>>());
    expect(tree.rootNodes, hasLength(1));
    expect(tree.rootNodes.single.data, isA<Directory>());

    if (!Platform.isWindows) {
      Link('$root${sep}link').createSync('$root${sep}a');
      final links = await scanner.scan(root);
      final link = links.singleWhere((e) => e.path.endsWith('link'));
      expect(link.isFile, isTrue);
      expect(link.data, isA<Link>());
    }

    final hidden = await const DirectoryScanner(includeHidden: true).scan(root);
    expect(hidden.any((e) => e.path.endsWith('.env')), isTrue);

    await expectLater(
      DirectoryScanner(skip: (_) => throw StateError('stop')).scan(root),
      throwsStateError,
      reason: 'an exception from skip aborts the scan',
    );

    if (!Platform.isWindows) {
      // A relative path that climbs above its start is scanned as absolute.
      final levels = Directory.current.absolute.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .length;
      final climbing = '${'../' * levels}${root.substring(1)}';
      final absolute = await const DirectoryScanner(
        maxDepth: 0,
      ).scanTree(climbing);
      expect(absolute.rootNodes.single.path.isAbsolute, isTrue);

      final locked = Directory('$root${sep}locked')..createSync();
      Process.runSync('chmod', ['000', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
      final errors = <FileSystemException>[];
      final walked = await DirectoryScanner(onError: errors.add).scan(root);
      if (Process.runSync('id', ['-u']).stdout.toString().trim() != '0') {
        expect(errors, hasLength(1), reason: 'onError gets unreadable dirs');
      }
      expect(
        walked.any((e) => e.path == locked.path),
        isTrue,
        reason: 'the unreadable directory stays an entry',
      );
      Process.runSync('chmod', ['755', locked.path]);

      final followed = await const DirectoryScanner(
        followLinks: true,
      ).scan(root);
      final linked = followed.singleWhere((e) => e.path.endsWith('link'));
      expect(linked.isDirectory, isTrue);
      expect(linked.data, isA<Directory>());
    }

    await expectLater(
      scanner.scan('$root${sep}missing'),
      throwsA(isA<PathNotFoundException>()),
    );
    await expectLater(
      scanner.scan(file.path),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      const DirectoryScanner(maxDepth: -1).scan(root),
      throwsArgumentError,
    );
  });

  test('use-directory-tree reference claims match the shipped API', () {
    final failures = <String>[];
    void check(String claim, Object? actual, Object? expected) {
      if (actual.toString() == expected.toString()) return;
      failures.add(
        '$claim\n    skill says: $expected\n    actual    : $actual',
      );
    }

    final tree = DirectoryTree.fromPaths([
      '/repo/lib/src/tree.dart',
      '/repo/lib/main.dart',
      '/repo/README.md',
    ]);
    final repo = tree.roots.single;
    final lib = tree.idOf('/repo/lib')!;
    final src = tree.idOf('/repo/lib/src')!;
    final mainDart = tree.idOf('/repo/lib/main.dart')!;

    // DirectoryTree and DirectoryTreeBuilder.
    check('rootOf a top-level node is itself', tree.rootOf(repo)?.id, repo);
    check('rootOf', tree.rootOf(mainDart)?.id, repo);
    check('a file subtree size is 1', tree.subtreeSizeOf(mainDart), 1);
    check(
      'issues are not compared',
      DirectoryTree.fromPaths(['/r/a', '']) ==
          DirectoryTree.fromPaths(['/r/a']),
      true,
    );
    final builder = DirectoryTreeBuilder<Object?>()
      ..addFile('/A/x.txt')
      ..addFile('/a/x.txt');
    check(
      'builder.contains counts entries only',
      builder.contains('/a'),
      false,
    );
    builder.options = const TreeOptions(paths: PathPolicy.caseInsensitive);
    check('a new PathPolicy re-keys and merges entries', builder.length, 1);
    final folding = DirectoryTreeBuilder<Object?>(
      options: const TreeOptions(paths: PathPolicy.caseInsensitive),
    )..addFile('/a/b.txt');
    check('remove compares by id under the policy', folding.remove('/A'), 1);
    check(
      'TreeEntry == ignores the type argument',
      _equal(const TreeEntry<int>.file('a'), const TreeEntry<String>.file('a')),
      true,
    );
    check(
      'labels fall back to the full path',
      DirectoryTree.fromPaths([
        r'C:\src\a',
        r'D:\src\b',
      ]).rootNodes.map((n) => n.label),
      '(C:/src, D:/src)',
    );

    // TreePath and PathPolicy.
    check('C:foo is relative', TreePath.parse('C:foo').isAbsolute, false);
    check('three separators collapse to /', TreePath.parse('///a').root, '/');
    check('UNC without a share', TreePath.parse('//server').root, '//server/');
    check('.. stays at an absolute root', TreePath.parse('/../a'), '/a');
    check(
      'child rejects ..',
      _throws<ArgumentError>(() => TreePath.parse('/a').child('..')),
      true,
    );
    check(
      'compareTo uses code units',
      TreePath.parse('/B').compareTo(TreePath.parse('/a')) < 0,
      true,
    );
    check(
      'tryParse catches only FormatException',
      _throws<StateError>(
        () => PathPolicy(
          unicodeNormalizer: (p) => throw StateError('x'),
        ).tryParse('/a'),
      ),
      true,
    );
    check('input is not trimmed', TreePath.parse(' a ').segments, '[ a ]');

    // Options.
    check(
      'a fixed root inside another collapses',
      DirectoryTree.fromPaths(
        ['/w/a/x.txt'],
        options: const TreeOptions(roots: TreeRoots.fixed(['/w', '/w/a'])),
      ).roots,
      '[/w]',
    );
    check(
      'TreeOrder.by<T> on another data type throws TypeError while building',
      _throws<TypeError>(
        () => DirectoryTree.fromPaths([
          '/r/a',
          '/r/b',
        ], options: TreeOptions(order: TreeOrder.by<int>((a, b) => 0))),
      ),
      true,
    );
    check(
      'TreeIssue toString',
      DirectoryTree.fromPaths(
        ['/x/b.txt'],
        options: const TreeOptions(roots: TreeRoots.fixed(['/w'])),
      ).issues.single,
      'TreeIssue.outsideRoots(/x/b.txt): The entry is outside every fixed '
          'root; the entry was dropped.',
    );

    // TreeRows and TreeRow.
    final all = tree.flatten();
    check(
      'guides.length == depth',
      all.every((r) => r.guides.length == r.depth),
      true,
    );
    check(
      'reveal returns the same rows when visible',
      identical(all.reveal(mainDart), all),
      true,
    );
    final filtered = tree.flatten(filter: TreeQuery.parse('main'));
    check(
      'reveal returns the same rows when the filter hides the node',
      identical(filtered.reveal(src), filtered),
      true,
    );
    check(
      'toggleNode decides from expansion (what is shown)',
      tree
          .flatten(
            expansion: const ExpansionState.collapsed(),
            filter: TreeQuery.parse('main'),
          )
          .toggleNode(lib)
          .map((r) => r.label),
      '(repo, lib)',
    );
    check(
      'withExpansion(revealMatches: true) reveals matches',
      filtered
          .withExpansion(const ExpansionState.collapsed(), revealMatches: true)
          .map((r) => r.label),
      '(repo, lib, main.dart)',
    );
    final hidden = tree.flatten(showRoots: false);
    check('depth-0 rows have no parent row', hidden.parentIndexOf(0), null);
    check(
      'a hidden root never produces a row, even when it matches',
      tree.flatten(showRoots: false, filter: TreeQuery.parse('repo')).isEmpty,
      true,
    );
    check(
      'rows compare by value',
      tree.flatten().collapseNode(lib).expandNode(lib)[2] == all[2],
      true,
    );

    // ExpansionState.
    check(
      'fromJson throws FormatException on a missing key',
      _throws<FormatException>(() => ExpansionState.fromJson(const {})),
      true,
    );
    check(
      'fromJson ignores other keys',
      ExpansionState.fromJson(const {
        'default': 'expanded',
        'exceptions': <String>[],
        'extra': 1,
      }),
      'ExpansionState.expanded()',
    );
    const closed = ExpansionState.collapsed();
    check(
      'toggle always returns a new state',
      identical(closed.toggle(lib).toggle(lib), closed),
      false,
    );

    // TreeQuery and TreeFilter.
    final names = DirectoryTree.fromPaths([
      '/r/my dir/a b.txt',
      '/r/x!a.txt',
      '/r/bang!',
      '/r/straße.txt',
    ]);
    List<String> find(String text) => names.nodes
        .where(TreeQuery.parse(text).matches)
        .map((n) => n.name)
        .toList();
    check('a quote after a key', find('path:"my dir"'), '[my dir, a b.txt]');
    check('a lone ! searches for !', find('!'), '[bang!, x!a.txt]');
    check(
      'only the first ! negates',
      find('!!a type:file'),
      '[a b.txt, bang!, straße.txt]',
    );
    check('empty phrases are ignored', TreeQuery.parse('""').matchesAll, true);
    check('** is the same as *', find('**.txt'), find('*.txt'));
    check('no full case folding', find('STRASSE'), '[]');
    check(
      'İ has no simple case folding',
      TreeQuery.parse('istanbul').matches(
        DirectoryTree.fromPaths(['/r/İstanbul.txt']).nodeAt('/r/İstanbul.txt')!,
      ),
      false,
    );
    check(
      'case-insensitive ids are case-folded',
      PathPolicy.caseInsensitive.idOf(TreePath.parse('/R/README.md')).value,
      '/r/readme.md',
    );
    check(
      'queries are equal by source and caseSensitive',
      [
        TreeQuery.parse('a b') == TreeQuery.parse('a b'),
        TreeQuery.parse('a  b') == TreeQuery.parse('a b'),
      ],
      [true, false],
    );
    final negated = TreeQuery.parse('a').negate();
    check(
      'negating a negation returns the original',
      negated.negate() == TreeQuery.parse('a'),
      true,
    );

    // SelectionState.
    final ranged = SelectionState(
      mode: SelectionMode.multiple,
      selected: [mainDart, lib],
      anchor: repo,
    );
    check(
      'toJson shape',
      ranged.toJson(),
      '{mode: multiple, selected: [/repo/lib, /repo/lib/main.dart], '
          'anchor: /repo}',
    );
    check(
      'withMode(single) clears when no single id stands out',
      ranged.withMode(SelectionMode.single).isEmpty,
      true,
    );
    check(
      'withMode(single) keeps the only selected id as the anchor',
      SelectionState(
        mode: SelectionMode.multiple,
        selected: [lib],
      ).withMode(SelectionMode.single).anchor,
      lib,
    );
    check(
      'single-mode addAll keeps the last id',
      const SelectionState.empty().addAll([lib, src]).selected,
      {src},
    );
    check('check keeps the anchor', ranged.check(tree, src).anchor, repo);

    // ListDiff and TreeDiff.
    final diff = ListDiff.compute(
      ['a', 'b'],
      ['x', 'a', 'b'],
      keyOf: (v) => v,
      equals: (x, y) => false,
    );
    check('changedIndices index into after', diff.changedIndices, [1, 2]);
    check(
      'diff lists are unmodifiable',
      _throws<UnsupportedError>(() => diff.removedIndices.add(0)),
      true,
    );

    // TreeStyle.
    check(
      'TreeStyle presets',
      [TreeStyle.unicode.lastBranch, TreeStyle.ascii.lastBranch],
      ['└── ', '`-- '],
    );

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('migrate-directory-tree-v1-to-v2 claims match the shipped API', () {
    final failures = <String>[];
    void check(String claim, Object? actual, Object? expected) {
      if (actual.toString() == expected.toString()) return;
      failures.add(
        '$claim\n    skill says: $expected\n    actual    : $actual',
      );
    }

    // dart fix: exactly three renames.
    final fixData = File('lib/fix_data.yaml').readAsStringSync();
    check(
      'dart fix renames exactly these fields',
      RegExp(r"field: '(\w+)'").allMatches(fixData).map((m) => m.group(1)),
      '(removeIndicesDesc, insertIndicesAsc, fullPath)',
    );
    check(
      'to these names',
      RegExp(r"newName: '(\w+)'").allMatches(fixData).map((m) => m.group(1)),
      '(removedIndices, insertedIndices, path)',
    );

    // Preconditions.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    check(
      'requires Dart ^3.8.0',
      RegExp(r'sdk:\s*(\S+)').firstMatch(pubspec)!.group(1),
      '^3.8.0',
    );
    final dependencies = RegExp(
      r'^dependencies:\n((?:  .+\n)+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    check(
      'depends only on meta',
      RegExp(
        r'^  (\w+):',
        multiLine: true,
      ).allMatches(dependencies).map((m) => m.group(1)),
      '(meta)',
    );

    // Core mapping (each line compiles only if the 2.0.0 name exists).
    final tree = DirectoryTree.fromPaths([
      '/repo/lib/main.dart',
      '/repo/lib/src/tree.dart',
      '/repo/README.md',
    ]);
    final lib = tree.idOf('/repo/lib')!;
    check('roots replace visibleRootId', tree.rootNodes.single.name, 'repo');
    check(
      'withExpanded replaces ExpansionSet(initiallyExpanded:)',
      ExpansionState.withExpanded([lib]).isExpanded(lib),
      true,
    );
    check(
      'setExpanded takes a named expanded:',
      const ExpansionState.collapsed().setExpanded(lib, expanded: true),
      'ExpansionState.withExpanded([/repo/lib])',
    );
    check(
      'SelectionMode.multiple',
      SelectionMode.values.map((m) => m.name),
      '(single, multiple)',
    );
    check(
      'CheckState',
      CheckState.values.map((m) => m.name),
      '(unchecked, partial, checked)',
    );
    check('node.isExplicit replaces origin', tree[lib]!.isExplicit, false);
    check(
      'TreePath.parse(p).name replaces basename',
      TreePath.parse('/a/b.txt').name,
      'b.txt',
    );
    check(
      'extension().toLowerCase() replaces extensionLower',
      TreePath.parse('/a/B.TXT').extension.toLowerCase(),
      '.txt',
    );
    check(
      'nodeAt takes a real path',
      tree.nodeAt('/repo/lib/main.dart')?.name,
      'main.dart',
    );
    check(
      'ListDiff no-op test',
      ListDiff.compute([1], [1], keyOf: (v) => v).removedIndices.isEmpty,
      true,
    );

    // Behavior checklist.
    check(
      'paths are case sensitive by default',
      DirectoryTree.fromPaths(['/Repo/a', '/repo/a']).fileCount,
      2,
    );
    check(
      'ids are canonical paths, lowercased when case-insensitive',
      DirectoryTree.fromPaths(
        ['/Repo/Lib/a.dart'],
        options: const TreeOptions(paths: PathPolicy.caseInsensitive),
      ).files.single.id.value,
      '/repo/lib/a.dart',
    );
    check(
      'no synthetic root: two folders are two depth-0 rows',
      DirectoryTree.fromPaths([
        '/a/x.txt',
        '/b/y.txt',
      ]).flatten().where((r) => r.depth == 0).length,
      2,
    );
    check(
      'compactFolders draws single-folder chains on one row',
      DirectoryTree.fromPaths([
        '/w/a/b/x.txt',
        '/w/y.txt',
      ]).flatten(compactFolders: true)[1].label,
      'a/b',
    );
    check(
      'names come from the last path segment',
      DirectoryTree.build([
        const TreeEntry<Object?>.file('/r/real.txt'),
      ]).files.single.name,
      'real.txt',
    );
    check(
      'duplicates: the later entry wins',
      DirectoryTree<String>.build([
        const TreeEntry.file('/r/a', data: 'first'),
        const TreeEntry.file('/r/a', data: 'second'),
      ]).files.single.data,
      'second',
    );
    check(
      'whitespace is kept',
      DirectoryTree.fromPaths([' /r/a.txt ']).files.single.name,
      'a.txt ',
    );
    check(
      'an escaping relative path is an invalidPath issue',
      DirectoryTree.fromPaths(['../up/a.txt']).issues.single.kind,
      TreeIssueKind.invalidPath,
    );
    check(
      'UNC roots are kept',
      TreePath.parse(r'\\server\share\a.txt').root,
      '//server/share/',
    );
    check(
      'natural sibling order',
      DirectoryTree.fromPaths([
        '/d/file10',
        '/d/file2',
      ]).files.map((n) => n.name),
      '(file2, file10)',
    );
    check(
      'colliding top-level labels read like paths',
      DirectoryTree.fromPaths([
        '/a/src/x',
        '/b/src/y',
      ]).rootNodes.map((n) => n.label),
      '(a/src, b/src)',
    );
    final search = tree.flatten(
      expansion: const ExpansionState.collapsed(),
      filter: TreeQuery.parse('main'),
    );
    check(
      'expandMatches adds ancestors to the expansion, so they can collapse',
      search.collapseNode(lib).map((r) => r.label),
      '(repo, lib)',
    );
    check(
      'ext: never matches directories',
      TreeQuery.parse(
        'ext:d',
      ).matches(DirectoryTree.fromPaths(['/r/x.d/']).nodes.last),
      false,
    );
    check(
      '* is a glob; quote it to search literally',
      [
        TreeQuery.parse(
          'a*b',
        ).matches(DirectoryTree.fromPaths(['/r/axxb']).files.single),
        TreeQuery.parse(
          '"a*b"',
        ).matches(DirectoryTree.fromPaths(['/r/axxb']).files.single),
      ],
      [true, false],
    );
    check(
      'hasChildren is false when the filter hides every child',
      tree
          .flatten(filter: TreeQuery.parse('type:d'))
          .rowOf(tree.idOf('/repo/lib/src')!)!
          .hasChildren,
      false,
    );
    check(
      'flatten defaults to everything expanded',
      tree.flatten().length,
      tree.length,
    );
    const state = ExpansionState.collapsed();
    final ignored = state.expand(lib); // the skill: assign every result
    check(
      'state classes are immutable',
      [state.isExpanded(lib), ignored.isExpanded(lib)],
      [false, true],
    );
    check(
      'single-mode toggle of the selected id clears',
      const SelectionState.empty().select(lib).toggle(lib).isEmpty,
      true,
    );
    check(
      'an unchecked empty subfolder makes the parent partial',
      const SelectionState.empty(mode: SelectionMode.multiple)
          .check(tree, lib)
          .checkStateOf(
            tree.rebuild((b) => b.addDirectory('/repo/lib/empty')),
            lib,
          ),
      CheckState.partial,
    );
    check(
      'changedIndices make isEmpty stricter than isNoop',
      ListDiff.compute([1], [2], keyOf: (v) => 'same').isEmpty,
      false,
    );
    check(
      'extension is empty for a name ending in a dot',
      TreePath.parse('/r/name.').extension,
      '',
    );

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

/// The ```dart blocks of every markdown file under the skills directory.
List<String> _skillBlocks() => [
  for (final file
      in Directory(_skillsDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
    for (final match in RegExp(
      r'^```dart\n([\s\S]*?)^```$',
      multiLine: true,
    ).allMatches(file.readAsStringSync()))
      match.group(1)!,
];

/// Trims every line, collapses inner whitespace, and drops blank lines, so
/// indentation inside a test does not hide a copied block.
String _normalize(String code) => code
    .split('\n')
    .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((line) => line.isNotEmpty)
    .join('\n');

/// A `print(...); // output` line; group 1 is the promised output.
final _printLine = RegExp(r'^\s*print\(.*\);\s*// (.*)$', multiLine: true);

/// The outputs that `print(...); // output` lines in [block] promise.
List<String> _expectedPrints(String block) => [
  for (final match in _printLine.allMatches(block)) match.group(1)!,
];

/// Runs [body] and returns everything it printed, one entry per `print`.
Future<List<String>> _prints(FutureOr<void> Function() body) async {
  final printed = <String>[];
  await runZoned(
    () async => body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

/// A switch over the sealed node classes; it compiles only while
/// `TreeNode` has exactly these two subclasses.
String _kindName(TreeNode<Object?> node) => switch (node) {
  FileNode() => 'file',
  DirectoryNode() => 'dir',
};

String _identity(String path) => path;

bool _throws<E>(void Function() body) {
  try {
    body();
  } on Object catch (error) {
    return error is E;
  }
  return false;
}

Type _staticType<T>(T value) => T;

Type _type<T>() => T;

/// Whether [rows] can be used where a `List<TreeRow<Object?>>` is expected.
bool _isRowList(List<TreeRow<Object?>> rows) => rows.isNotEmpty;

bool _equal(Object a, Object b) => a == b;
