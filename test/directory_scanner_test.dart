@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/io.dart';
import 'package:directory_tree/src/io/extended_length_path.dart';
import 'package:directory_tree/src/io/host_path.dart';
import 'package:test/test.dart';

/// Every scan result, described relative to [base] as `kind:path:Data`, so
/// expectations read like a listing. `kind` is `d` or `f`; `Data` is the
/// most specific of Link, Directory, File.
List<String> describe(String base, List<TreeEntry<FileSystemEntity>> entries) {
  return [
    for (final entry in entries)
      '${entry.isDirectory ? 'd' : 'f'}:${relative(base, entry.path)}:'
          '${dataType(entry.data)}',
  ];
}

String relative(String base, String path) {
  if (path == base) return '.';
  expect(path.startsWith(base), isTrue, reason: '$path is outside $base');
  return path.substring(base.length + 1).replaceAll(r'\', '/');
}

String dataType(FileSystemEntity? data) => switch (data) {
  Link() => 'Link',
  Directory() => 'Directory',
  File() => 'File',
  _ => 'unexpected $data',
};

/// Creates directories (paths ending in '/') and files under [base].
void create(Directory base, List<String> paths) {
  for (final path in paths) {
    final full = '${base.path}/$path';
    if (path.endsWith('/')) {
      Directory(full).createSync(recursive: true);
    } else {
      File(full).createSync(recursive: true);
    }
  }
}

/// Scans with both entry points, checks they agree, and returns the sync
/// description.
Future<List<String>> scanBoth(DirectoryScanner scanner, String path) async {
  final sync = describe(path, scanner.scanSync(path));
  final async = describe(path, await scanner.scan(path));
  expect(async, sync, reason: 'scan and scanSync disagree');
  return sync;
}

bool get canChmod {
  if (Platform.isWindows) return false;
  final id = Process.runSync('id', ['-u']);
  return id.exitCode == 0 && (id.stdout as String).trim() != '0';
}

void main() {
  late Directory base;

  setUp(() {
    base = Directory.systemTemp.createTempSync('directory_scanner_test');
    create(base, [
      'a/a.txt',
      'a/b/b.txt',
      'a/b/c/deep.txt',
      '.hidden/inner.txt',
      '.env',
      'empty/',
      'top.txt',
    ]);
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  const all = [
    'd:.:Directory',
    'd:a:Directory',
    'f:a/a.txt:File',
    'd:a/b:Directory',
    'f:a/b/b.txt:File',
    'd:a/b/c:Directory',
    'f:a/b/c/deep.txt:File',
    'd:empty:Directory',
    'f:top.txt:File',
  ];

  group('entries', () {
    test(
      'lists the root and every non-hidden entity, sorted by path',
      () async {
        expect(await scanBoth(const DirectoryScanner(), base.path), all);
      },
    );

    test('data is the entity at the same path', () {
      for (final entry in const DirectoryScanner().scanSync(base.path)) {
        expect(entry.data!.path, entry.path);
      }
    });

    test('sorts by UTF-16 code units, not by name or kind', () async {
      create(base, ['Z.txt', '_x/', 'a-b.txt', 'a.txt']);
      final paths = const DirectoryScanner()
          .scanSync(base.path)
          .map((entry) => entry.path)
          .toList();
      expect(paths, [...paths]..sort());
      final names = describe(
        base.path,
        const DirectoryScanner().scanSync(base.path),
      ).map((line) => line.split(':')[1]).toList();
      // 'Z' < '_' < 'a', and '-' < '.' < '/'.
      expect(names, [
        '.',
        'Z.txt',
        '_x',
        'a',
        'a-b.txt',
        'a.txt',
        'a/a.txt',
        'a/b',
        'a/b/b.txt',
        'a/b/c',
        'a/b/c/deep.txt',
        'empty',
        'top.txt',
      ]);
      expect(
        await scanBoth(const DirectoryScanner(), base.path),
        hasLength(13),
      );
    });

    test('scan yields to the event loop between directory reads', () async {
      create(base, [for (var i = 0; i < 50; i++) 'many/d$i/']);
      var ticks = 0;
      final timer = Timer.periodic(Duration.zero, (_) => ticks++);
      addTearDown(timer.cancel);
      await const DirectoryScanner().scan(base.path);
      expect(ticks, greaterThan(0));
    });

    test('a deep chain is walked without recursion', () async {
      final chain = List.filled(200, 'd').join('/');
      create(base, ['$chain/leaf.txt']);
      final errors = <FileSystemException>[];
      final result = await scanBoth(
        DirectoryScanner(onError: errors.add),
        base.path,
      );
      expect(errors, isEmpty);
      expect(result, contains('f:$chain/leaf.txt:File'));
      expect(result, hasLength(all.length + 201));
    });
  });

  group('includeHidden', () {
    test('false omits hidden files and does not enter hidden directories', () {
      final result = describe(
        base.path,
        const DirectoryScanner().scanSync(base.path),
      );
      expect(result.where((line) => line.contains('.hidden')), isEmpty);
      expect(result.where((line) => line.contains('.env')), isEmpty);
    });

    test('true includes hidden files and directories', () async {
      expect(
        await scanBoth(const DirectoryScanner(includeHidden: true), base.path),
        [
          'd:.:Directory',
          'f:.env:File',
          'd:.hidden:Directory',
          'f:.hidden/inner.txt:File',
          ...all.skip(1),
        ],
      );
    });

    test('a hidden root is always scanned', () async {
      final hidden = '${base.path}/.hidden';
      expect(await scanBoth(const DirectoryScanner(), hidden), [
        'd:.:Directory',
        'f:inner.txt:File',
      ]);
    });
  });

  group('maxDepth', () {
    test('0 returns only the root', () async {
      expect(await scanBoth(const DirectoryScanner(maxDepth: 0), base.path), [
        'd:.:Directory',
      ]);
    });

    test('1 adds the direct children without listing them', () async {
      expect(await scanBoth(const DirectoryScanner(maxDepth: 1), base.path), [
        'd:.:Directory',
        'd:a:Directory',
        'd:empty:Directory',
        'f:top.txt:File',
      ]);
    });

    test('2 lists one more level', () async {
      expect(await scanBoth(const DirectoryScanner(maxDepth: 2), base.path), [
        'd:.:Directory',
        'd:a:Directory',
        'f:a/a.txt:File',
        'd:a/b:Directory',
        'd:empty:Directory',
        'f:top.txt:File',
      ]);
    });

    test('null has no limit', () async {
      expect(await scanBoth(const DirectoryScanner(), base.path), all);
    });

    test('negative throws ArgumentError from every entry point', () async {
      const scanner = DirectoryScanner(maxDepth: -1);
      expect(() => scanner.scanSync(base.path), throwsArgumentError);
      await expectLater(scanner.scan(base.path), throwsArgumentError);
      await expectLater(scanner.scanTree(base.path), throwsArgumentError);
    });
  });

  group('skip', () {
    test(
      'skipping a directory prunes its subtree without visiting it',
      () async {
        final seen = <String>[];
        final scanner = DirectoryScanner(
          skip: (entity) {
            seen.add(relative(base.path, entity.path));
            return entity is Directory && entity.path.endsWith('b');
          },
        );
        expect(await scanBoth(scanner, base.path), [
          'd:.:Directory',
          'd:a:Directory',
          'f:a/a.txt:File',
          'd:empty:Directory',
          'f:top.txt:File',
        ]);
        // Never called for the root, hidden entities, or anything under a/b.
        expect(seen.toSet(), {'a', 'a/a.txt', 'a/b', 'empty', 'top.txt'});
      },
    );

    test('skipping files keeps their directories', () async {
      final scanner = DirectoryScanner(
        skip: (entity) => entity is File && entity.path.endsWith('.txt'),
      );
      expect(await scanBoth(scanner, base.path), [
        'd:.:Directory',
        'd:a:Directory',
        'd:a/b:Directory',
        'd:a/b/c:Directory',
        'd:empty:Directory',
      ]);
    });
  });

  group('errors', () {
    test('a missing path throws PathNotFoundException', () async {
      final missing = '${base.path}/missing';
      const scanner = DirectoryScanner();
      expect(
        () => scanner.scanSync(missing),
        throwsA(
          isA<PathNotFoundException>().having((e) => e.path, 'path', missing),
        ),
      );
      await expectLater(
        scanner.scan(missing),
        throwsA(isA<PathNotFoundException>()),
      );
      await expectLater(
        scanner.scanTree(missing),
        throwsA(isA<PathNotFoundException>()),
      );
    });

    test('an empty path throws PathNotFoundException', () async {
      // scanTree must not turn '' into the current directory's absolute
      // path while handling relative paths that escape their start.
      const scanner = DirectoryScanner();
      expect(() => scanner.scanSync(''), throwsA(isA<PathNotFoundException>()));
      await expectLater(
        scanner.scanTree(''),
        throwsA(isA<PathNotFoundException>()),
      );
    });

    test('a file path throws FileSystemException', () async {
      final file = '${base.path}/top.txt';
      final notADirectory = isA<FileSystemException>()
          .having((e) => e, 'type', isNot(isA<PathNotFoundException>()))
          .having((e) => e.path, 'path', file);
      expect(
        () => const DirectoryScanner().scanSync(file),
        throwsA(notADirectory),
      );
      await expectLater(
        const DirectoryScanner().scan(file),
        throwsA(notADirectory),
      );
    });

    group('unreadable directory', () {
      setUp(() {
        Process.runSync('chmod', ['000', '${base.path}/a/b']);
        addTearDown(
          () => Process.runSync('chmod', ['755', '${base.path}/a/b']),
        );
      });

      test(
        'is reported, its error goes to onError, and the walk continues',
        () async {
          final errors = <FileSystemException>[];
          final scanner = DirectoryScanner(onError: errors.add);
          expect(await scanBoth(scanner, base.path), [
            'd:.:Directory',
            'd:a:Directory',
            'f:a/a.txt:File',
            'd:a/b:Directory',
            'd:empty:Directory',
            'f:top.txt:File',
          ]);
          // One error from scanSync and one from scan.
          expect(errors, hasLength(2));
          for (final error in errors) {
            expect(error, isA<PathAccessException>());
            expect(error.path, contains('a${Platform.pathSeparator}b'));
          }
        },
      );

      test('is ignored by default', () async {
        expect(
          await scanBoth(const DirectoryScanner(), base.path),
          contains('d:a/b:Directory'),
        );
      });

      test('an onError that throws aborts the scan', () async {
        final scanner = DirectoryScanner(
          onError: (error) => throw StateError('stop'),
        );
        expect(() => scanner.scanSync(base.path), throwsStateError);
        await expectLater(scanner.scan(base.path), throwsStateError);
      });
    }, skip: canChmod ? false : 'needs chmod and a non-root user');
  });

  group(
    'links',
    () {
      setUp(() {
        Link('${base.path}/file-link').createSync('${base.path}/top.txt');
        Link('${base.path}/dir-link').createSync('${base.path}/a/b');
        Link('${base.path}/broken').createSync('${base.path}/nowhere');
      });

      test('are reported as files with Link data when not followed', () async {
        expect(await scanBoth(const DirectoryScanner(), base.path), [
          'd:.:Directory',
          'd:a:Directory',
          'f:a/a.txt:File',
          'd:a/b:Directory',
          'f:a/b/b.txt:File',
          'd:a/b/c:Directory',
          'f:a/b/c/deep.txt:File',
          'f:broken:Link',
          'f:dir-link:Link',
          'd:empty:Directory',
          'f:file-link:Link',
          'f:top.txt:File',
        ]);
      });

      test('are resolved when followed; broken links stay links', () async {
        expect(
          await scanBoth(const DirectoryScanner(followLinks: true), base.path),
          [
            'd:.:Directory',
            'd:a:Directory',
            'f:a/a.txt:File',
            'd:a/b:Directory',
            'f:a/b/b.txt:File',
            'd:a/b/c:Directory',
            'f:a/b/c/deep.txt:File',
            'f:broken:Link',
            'd:dir-link:Directory',
            'f:dir-link/b.txt:File',
            'd:dir-link/c:Directory',
            'f:dir-link/c/deep.txt:File',
            'd:empty:Directory',
            'f:file-link:File',
            'f:top.txt:File',
          ],
        );
      });

      test('followed directories count toward maxDepth', () async {
        final result = await scanBoth(
          const DirectoryScanner(followLinks: true, maxDepth: 2),
          base.path,
        );
        expect(
          result,
          containsAll(['d:dir-link/c:Directory', 'f:dir-link/b.txt:File']),
        );
        expect(result, isNot(contains('f:dir-link/c/deep.txt:File')));
      });

      test('skip sees the resolved entity of a followed link', () async {
        final types = <String, String>{};
        final scanner = DirectoryScanner(
          followLinks: true,
          skip: (entity) {
            types[relative(base.path, entity.path)] = dataType(entity);
            return entity is Directory && entity.path.endsWith('dir-link');
          },
        );
        final result = await scanBoth(scanner, base.path);
        expect(result.where((line) => line.contains('dir-link')), isEmpty);
        expect(types['dir-link'], 'Directory');
        expect(types['file-link'], 'File');
        expect(types['broken'], 'Link');
      });

      test('a link to an ancestor is reported but never entered', () async {
        Link('${base.path}/a/b/up').createSync(base.path);
        Link('${base.path}/a/self').createSync('${base.path}/a/self');
        Link('${base.path}/a/here').createSync('.');
        final result = await scanBoth(
          const DirectoryScanner(followLinks: true),
          base.path,
        );
        expect(
          result,
          containsAll([
            'f:a/b/up:Link',
            'f:a/self:Link',
            'f:a/here:Link',
            // The ancestor link reached again through dir-link is also a cycle.
            'f:dir-link/up:Link',
          ]),
        );
        expect(result.where((line) => line.contains('up/')), isEmpty);
        expect(result.where((line) => line.contains('here/')), isEmpty);
      });

      test('a link above the scan root does not loop back into it', () async {
        // Scanning a/: a/b/out points at the parent of the scan root, so the
        // walk enters base once and meets a/ again as a real directory that is
        // already on the branch; it is reported but not entered.
        Link('${base.path}/a/b/out').createSync(base.path);
        final root = '${base.path}/a';
        final result = await scanBoth(
          const DirectoryScanner(followLinks: true),
          root,
        );
        expect(result, contains('d:b/out:Directory'));
        expect(result, contains('d:b/out/a:Directory'));
        expect(result.where((line) => line.contains('b/out/a/')), isEmpty);
        expect(result, contains('f:b/out/top.txt:File'));
      });

      test('a root that is a link to a directory is scanned', () async {
        final linked = '${base.path}/dir-link';
        expect(await scanBoth(const DirectoryScanner(), linked), [
          'd:.:Directory',
          'f:b.txt:File',
          'd:c:Directory',
          'f:c/deep.txt:File',
        ]);
      });

      test('a broken link as the root throws PathNotFoundException', () {
        expect(
          () => const DirectoryScanner().scanSync('${base.path}/broken'),
          throwsA(isA<PathNotFoundException>()),
        );
      });
    },
    skip: Platform.isWindows
        ? 'symbolic links need privileges on Windows'
        : false,
  );

  group('followed links past MAX_PATH', () {
    /// Creates a directory link (a junction on Windows) at [path] to
    /// [target], through the extended-length path when the ordinary one
    /// is refused for its length.
    void link(String path, String target) {
      try {
        Link(path).createSync(target);
      } on FileSystemException {
        final extended = windowsExtendedLengthPath(File(path).absolute.path);
        if (extended == null) rethrow;
        Link(extended).createSync(target);
      }
    }

    test('are followed, and a link to its own directory is a cycle', () async {
      final separator = Platform.pathSeparator;
      create(base, ['target/inner.txt', 'target/sub/']);
      final chain = List.filled(150, 'd').join('/');
      create(base, ['$chain/']);
      final bottom = [base.path, ...List.filled(150, 'd')].join(separator);
      expect('$bottom${separator}link'.length, greaterThan(windowsMaxPath));
      link('$bottom${separator}link', '${base.path}${separator}target');
      link('$bottom${separator}up', bottom);

      final errors = <FileSystemException>[];
      final result = await scanBoth(
        DirectoryScanner(followLinks: true, onError: errors.add),
        base.path,
      );
      expect(errors, isEmpty);
      expect(
        result,
        containsAll([
          'd:$chain/link:Directory',
          'f:$chain/link/inner.txt:File',
          'd:$chain/link/sub:Directory',
          'f:$chain/up:Link',
        ]),
      );
      expect(result.where((line) => line.contains('up/')), isEmpty);
    });
  }, skip: Platform.isWindows ? false : 'MAX_PATH applies only on Windows');

  group('a root past MAX_PATH', () {
    /// Creates a file or, when [path] ends with a separator, a directory,
    /// through the extended-length path when the ordinary one is refused
    /// for its length.
    void createLong(String path) {
      void make(String target) {
        if (path.endsWith(Platform.pathSeparator)) {
          Directory(target).createSync(recursive: true);
        } else {
          File(target).createSync(recursive: true);
        }
      }

      try {
        make(path);
      } on FileSystemException {
        final extended = windowsExtendedLengthPath(File(path).absolute.path);
        if (extended == null) rethrow;
        make(extended);
      }
    }

    test('is scanned by its ordinary path, with and without links', () async {
      final separator = Platform.pathSeparator;
      final bottom = [base.path, ...List.filled(150, 'd')].join(separator);
      expect(bottom.length, greaterThan(windowsMaxPath));
      createLong('$bottom$separator');
      createLong('$bottom${separator}inner.txt');
      createLong('$bottom${separator}sub$separator');

      for (final followLinks in [false, true]) {
        final errors = <FileSystemException>[];
        final result = await scanBoth(
          DirectoryScanner(followLinks: followLinks, onError: errors.add),
          bottom,
        );
        expect(errors, isEmpty, reason: 'followLinks: $followLinks');
        expect(result, [
          'd:.:Directory',
          'f:inner.txt:File',
          'd:sub:Directory',
        ], reason: 'followLinks: $followLinks');
      }
    });
  }, skip: Platform.isWindows ? false : 'MAX_PATH applies only on Windows');

  group('relative paths', () {
    late Directory relativeBase;

    setUp(() {
      Directory('.dart_tool').createSync(recursive: true);
      relativeBase = Directory('.dart_tool').createTempSync('scanner_test');
      create(relativeBase, ['lib/main.dart', 'README.md']);
    });

    tearDown(() {
      if (relativeBase.existsSync()) relativeBase.deleteSync(recursive: true);
    });

    test('stay relative', () async {
      expect(relativeBase.isAbsolute, isFalse);
      final entries = await const DirectoryScanner().scan(relativeBase.path);
      expect(entries.map((entry) => entry.path), [
        relativeBase.path,
        '${relativeBase.path}${Platform.pathSeparator}README.md',
        '${relativeBase.path}${Platform.pathSeparator}lib',
        '${relativeBase.path}${Platform.pathSeparator}lib'
            '${Platform.pathSeparator}main.dart',
      ]);
    });

    test('build a relative tree', () async {
      final tree = await const DirectoryScanner().scanTree(relativeBase.path);
      expect(tree.issues, isEmpty);
      final root = tree.rootNodes.single;
      expect(root.path.isAbsolute, isFalse);
      expect(root.path, TreePath.parse(relativeBase.path));
    });

    test("'.' is the relative path root", () async {
      final tree = await const DirectoryScanner(maxDepth: 0).scanTree('.');
      expect(tree.rootNodes.single.name, '.');
      expect(tree.rootNodes.single.data!.path, '.');
    });
  });

  group('scanTree', () {
    test('has the scanned directory as its single top-level node', () async {
      final tree = await const DirectoryScanner().scanTree(base.path);
      final root = tree.rootNodes.single;
      expect(root.path, TreePath.parse(base.path));
      expect(root.isExplicit, isTrue);
      expect(root.data, isA<Directory>());
      expect(root.data!.path, base.path);
    });

    test(
      'reads a leading // as / on Linux and macOS',
      () async {
        // Parsing reads `//var/...` as a UNC share root; the host reads `/`.
        final tree = await const DirectoryScanner().scanTree('/${base.path}');
        expect(tree.issues, isEmpty);
        final root = tree.rootNodes.single;
        expect(root.path, TreePath.parse(base.path));
        expect(root.data!.path, base.path);
      },
      skip: Platform.isWindows
          ? 'a leading // is a UNC root on Windows'
          : false,
    );

    test('POSIX spellings are respelled for the host reading', () {
      expect(posixTreeSpelling('//x/y'), '/x/y');
      expect(posixTreeSpelling('//'), '/');
      expect(posixTreeSpelling('///x'), '///x');
      expect(posixTreeSpelling('/x'), '/x');
      expect(posixTreeSpelling('C:'), './C:');
      expect(posixTreeSpelling('c:/x'), './c:/x');
      expect(posixTreeSpelling('C:x'), 'C:x');
      expect(posixTreeSpelling(r'C:\x'), r'C:\x');
      expect(posixTreeSpelling('x/C:'), 'x/C:');
      expect(posixTreeSpelling('\u212A:'), '\u212A:');
      expect(posixTreeSpelling(''), '');
      // Each result parses to the location Linux and macOS read.
      const policy = PathPolicy(backslashIsSeparator: false);
      expect(policy.parse(posixTreeSpelling('//x/y')), policy.parse('/x/y'));
      expect(policy.parse(posixTreeSpelling('//')), policy.parse('/'));
      final drive = policy.parse(posixTreeSpelling('C:/x'));
      expect(drive.isAbsolute, isFalse);
      expect(drive.segments, ['C:', 'x']);
    });

    test('contains a node for every scanned entry, with its data', () async {
      const scanner = DirectoryScanner(includeHidden: true);
      final entries = scanner.scanSync(base.path);
      final tree = await scanner.scanTree(base.path);
      expect(tree.issues, isEmpty);
      expect(tree.length, entries.length);
      expect(tree.nodes.every((node) => node.isExplicit), isTrue);
      for (final entry in entries) {
        final node = tree.nodeAt(entry.path);
        expect(node, isNotNull, reason: entry.path);
        expect(node!.kind, entry.kind);
        expect(node.data!.path, entry.path);
        expect(dataType(node.data), dataType(entry.data));
      }
    });

    test('scans a relative path that climbs above its start', () async {
      // Reach base from the current directory through more `..` segments
      // than the current directory has, without changing Directory.current
      // (it is process-wide). The extra `..` keeps the path escaping even
      // when the current directory is a root; `..` at a root stays there.
      final current = TreePath.parse(Directory.current.absolute.path);
      final target = TreePath.parse(base.absolute.path);
      if (current.root != target.root) {
        markTestSkipped('the temp directory is on another drive');
        return;
      }
      final escaping = [
        for (var i = 0; i <= current.segments.length; i++) '..',
        ...target.segments,
      ].join(Platform.pathSeparator);
      expect(TreePath.tryParse(escaping), isNull);
      expect(Directory(escaping).existsSync(), isTrue);

      const scanner = DirectoryScanner(includeHidden: true);
      final tree = await scanner.scanTree(escaping);
      expect(tree.issues, isEmpty);
      final root = tree.rootNodes.single;
      expect(root.path, target);
      expect(root.data, isA<Directory>());
      final expected = [
        for (final entry in scanner.scanSync(base.path))
          TreePath.parse(entry.path),
      ];
      expect(expected, hasLength(12));
      expect(tree.nodes.map((node) => node.path), unorderedEquals(expected));
      for (final node in tree.nodes) {
        expect(TreePath.parse(node.data!.path), node.path);
      }
    });

    test('passes options to the build', () async {
      final tree = await const DirectoryScanner().scanTree(
        base.path,
        options: const TreeOptions(order: TreeOrder.alphabetical),
      );
      final children = tree.childrenOf(tree.roots.single).map((n) => n.name);
      expect(children, ['a', 'empty', 'top.txt']);
      expect(tree.options.order, TreeOrder.alphabetical);
    });

    group('parses backslashes by the host rule', () {
      late Directory dir;

      setUp(() => dir = base.createTempSync('backslash'));

      /// Scans [dir] with [scanner] and checks the scanTree contract: one
      /// explicit top-level node, data on every node, no issues, and
      /// exactly [names] (literal file names) below the root.
      Future<DirectoryTree<FileSystemEntity>> expectIntact(
        List<String> names, {
        DirectoryScanner scanner = const DirectoryScanner(),
        TreeOptions options = const TreeOptions(),
      }) async {
        final tree = await scanner.scanTree(dir.path, options: options);
        expect(tree.issues, isEmpty);
        final root = tree.rootNodes.single;
        expect(root.path, TreePath.parse(dir.path));
        expect(root.data!.path, dir.path);
        expect(tree.nodes.every((node) => node.isExplicit), isTrue);
        expect(tree.nodes.every((node) => node.data != null), isTrue);
        final children = tree.childrenOf(tree.roots.single).toList();
        expect(children.map((node) => node.name), unorderedEquals(names));
        for (final node in children) {
          expect(node.data, isA<File>());
          expect(node.data!.path, '${dir.path}/${node.name}');
          expect(tree.parentOf(node.id)?.id, tree.roots.single);
        }
        expect(tree.length, names.length + 1);
        expect(tree.options.paths.backslashIsSeparator, isFalse);
        return tree;
      }

      test('a backslash in a name is not a separator', () async {
        create(dir, ['w', r'w\z.txt', 'ok.txt']);
        await expectIntact(['w', r'w\z.txt', 'ok.txt']);
      });

      test('a trailing backslash keeps two names apart', () async {
        create(dir, ['a', r'a\']);
        await expectIntact(['a', r'a\']);
      });

      test('backslash dot-dot segments never climb out', () async {
        create(dir, [r'x\..\..\outside.txt', r'..\..\hidden.txt']);
        await expectIntact([
          r'x\..\..\outside.txt',
          r'..\..\hidden.txt',
        ], scanner: const DirectoryScanner(includeHidden: true));
      });

      test('user options keep their settings but get the host rule', () async {
        create(dir, ['b', r'a\b.txt']);
        String fold(String path) => path;
        final options = TreeOptions(
          paths: PathPolicy(caseSensitive: false, unicodeNormalizer: fold),
          order: TreeOrder.alphabetical,
        );
        final tree = await expectIntact([r'a\b.txt', 'b'], options: options);
        expect(tree.childrenOf(tree.roots.single).map((node) => node.name), [
          r'a\b.txt',
          'b',
        ]);
        expect(tree.options.order, TreeOrder.alphabetical);
        expect(tree.options.roots, options.roots);
        expect(tree.options.paths.caseSensitive, isFalse);
        expect(tree.options.paths.unicodeNormalizer, fold);
        expect(
          tree.options,
          options.copyWith(
            paths: PathPolicy(
              caseSensitive: false,
              backslashIsSeparator: false,
              unicodeNormalizer: fold,
            ),
          ),
        );
      });

      test('the documented policy builds scan entries intact', () async {
        create(dir, ['w', r'w\z.txt']);
        final entries = await const DirectoryScanner().scan(dir.path);
        final hostTree = DirectoryTree.build(
          entries,
          options: TreeOptions(
            paths: PathPolicy(backslashIsSeparator: Platform.isWindows),
          ),
        );
        expect(hostTree.issues, isEmpty);
        expect(hostTree.length, 3);
        // The default policy splits the POSIX name, which is why scanTree
        // and the docs override it.
        final defaultTree = DirectoryTree.build(entries);
        expect(defaultTree.issues, isNotEmpty);
      });

      test('a scan path with a backslash in a name is scanned', () async {
        final odd = Directory('${dir.path}/odd\\name')..createSync();
        File('${odd.path}/inner.txt').createSync();
        final tree = await const DirectoryScanner().scanTree(odd.path);
        expect(tree.issues, isEmpty);
        expect(tree.rootNodes.single.data!.path, odd.path);
        expect(tree.rootNodes.single.name, r'odd\name');
        expect(tree.length, 2);
      });
    }, skip: Platform.isWindows ? r'\ is a separator on Windows' : false);
  });

  group('value semantics', () {
    bool skipNothing(FileSystemEntity entity) => false;

    test('equal settings are equal', () {
      expect(
        DirectoryScanner(maxDepth: 2, skip: skipNothing),
        DirectoryScanner(maxDepth: 2, skip: skipNothing),
      );
      expect(
        DirectoryScanner(maxDepth: 2, skip: skipNothing).hashCode,
        DirectoryScanner(maxDepth: 2, skip: skipNothing).hashCode,
      );
      expect(
        const DirectoryScanner(),
        isNot(const DirectoryScanner(includeHidden: true)),
      );
      expect(
        const DirectoryScanner(),
        isNot(const DirectoryScanner(followLinks: true)),
      );
      expect(
        const DirectoryScanner(),
        isNot(const DirectoryScanner(maxDepth: 0)),
      );
    });

    test('toString names the settings', () {
      expect(
        DirectoryScanner(maxDepth: 3, skip: skipNothing).toString(),
        'DirectoryScanner(includeHidden: false, followLinks: false, '
        'maxDepth: 3, skip: set, onError: none)',
      );
    });
  });
}
