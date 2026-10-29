import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

typedef Range = ({int start, int end});

void main() {
  final tree = DirectoryTree<Never>.build(const [
    TreeEntry.file('/repo/lib/main.dart'),
    TreeEntry.file('/repo/lib/main.g.dart'),
    TreeEntry.file('/repo/lib/src/tree_query.dart'),
    TreeEntry.file('/repo/lib/src/Widget.DART'),
    TreeEntry.file('/repo/README.md'),
    TreeEntry.file('/repo/docs/My Notes.txt'),
    TreeEntry.file('/repo/test/a_test.dart'),
    TreeEntry.file('/repo/archive.tar.gz'),
    TreeEntry.file('/repo/.env'),
    TreeEntry.directory('/repo/build'),
    TreeEntry.file('/repo/weird!name.txt'),
    TreeEntry.file('/repo/foo:bar.txt'),
  ]);

  final allNames = {for (final node in tree.nodes) node.name};
  const dirs = {'repo', 'lib', 'src', 'docs', 'test', 'build'};
  final files = allNames.difference(dirs);
  const dartFiles = {
    'main.dart',
    'main.g.dart',
    'tree_query.dart',
    'Widget.DART',
    'a_test.dart',
  };

  Set<String> run(String query, {bool caseSensitive = false}) {
    final parsed = TreeQuery.parse(query, caseSensitive: caseSensitive);
    return {
      for (final node in tree.nodes)
        if (parsed.matches(node)) node.name,
    };
  }

  test('the fixture tree has the expected names', () {
    expect(allNames, hasLength(17));
    expect(files, hasLength(11));
  });

  group('parse and match', () {
    // query -> expected node names (case-insensitive unless marked).
    final cases = <String, Set<String>>{
      // Plain substring terms, AND, and case folding.
      'main': {'main.dart', 'main.g.dart'},
      'MAIN': {'main.dart', 'main.g.dart'},
      'main dart': {'main.dart', 'main.g.dart'},
      'main !g': {'main.dart'},
      'repo': {'repo'},
      'nope': {},
      // Whitespace variants separate terms.
      '\tmain\n': {'main.dart', 'main.g.dart'},
      'main\r\ndart': {'main.dart', 'main.g.dart'},
      'main　g': {'main.g.dart'},
      '  \t ': allNames,
      '': allNames,
      // Globs match the whole name.
      '*.dart': dartFiles,
      '*.g.dart': {'main.g.dart'},
      'main.????': {'main.dart'},
      '???': {'lib', 'src'},
      'ma*': {'main.dart', 'main.g.dart'},
      'ain*': {},
      '**.md': {'README.md'},
      '*': allNames,
      // Quoted phrases are literal and may contain whitespace.
      '"my notes"': {'My Notes.txt'},
      '"my notes': {'My Notes.txt'},
      'my notes': {'My Notes.txt'},
      '"*.dart"': {},
      '"ext:dart"': {},
      '"a"b': {'foo:bar.txt'},
      '""': allNames,
      '"': allNames,
      // ext:
      'ext:dart': dartFiles,
      'ext:.dart': dartFiles,
      'EXT:DART': dartFiles,
      'Ext:Dart': dartFiles,
      'ext:md,txt': {
        'README.md',
        'My Notes.txt',
        'weird!name.txt',
        'foo:bar.txt',
      },
      'ext:.md,.txt': {
        'README.md',
        'My Notes.txt',
        'weird!name.txt',
        'foo:bar.txt',
      },
      'ext:dart,': dartFiles,
      'ext:gz': {'archive.tar.gz'},
      'ext:tar.gz': {'archive.tar.gz'},
      'ext:env': {},
      'ext:"md"': {'README.md'},
      // ext: never matches directories, even when the name would.
      'ext:dart type:dir': {},
      // type:
      'type:file': files,
      'type:f': files,
      'TYPE:FILE': files,
      'type:dir': dirs,
      'type:directory': dirs,
      'type:d': dirs,
      'type:Dir': dirs,
      'type:file ext:md': {'README.md'},
      // path:
      'path:lib/src': {'src', 'tree_query.dart', 'Widget.DART'},
      r'path:lib\src': {'src', 'tree_query.dart', 'Widget.DART'},
      'PATH:LIB/SRC': {'src', 'tree_query.dart', 'Widget.DART'},
      'path:/repo/docs': {'docs', 'My Notes.txt'},
      'path:"My Notes"': {'My Notes.txt'},
      'path:"docs/my': {'My Notes.txt'},
      'path:repo type:dir': dirs,
      // Unknown keys, empty values, bad values are plain text.
      'foo:bar': {'foo:bar.txt'},
      '"foo:bar"': {'foo:bar.txt'},
      ':bar': {'foo:bar.txt'},
      'ext:': {},
      'ext:.': {},
      'ext:,': {},
      'type:': {},
      'type:x': {},
      'path:': {},
      'path:""': {},
      'foo:"bar.txt"': {},
      // Negation.
      '!': {'weird!name.txt'},
      '! main': {},
      'weird!name': {'weird!name.txt'},
      '!main': allNames.difference({'main.dart', 'main.g.dart'}),
      '!!name': allNames.difference({'weird!name.txt'}),
      '!ext:dart': allNames.difference(dartFiles),
      '!type:dir': files,
      '!type:f': dirs,
      '!*.dart': allNames.difference(dartFiles),
      '!"my notes"': allNames.difference({'My Notes.txt'}),
      '!path:lib': allNames.difference({
        'lib',
        'src',
        'main.dart',
        'main.g.dart',
        'tree_query.dart',
        'Widget.DART',
      }),
      '!""': allNames,
      '!type:x': allNames,
    };

    for (final entry in cases.entries) {
      test('${_show(entry.key)} matches ${entry.value.length} nodes', () {
        expect(run(entry.key), entry.value);
      });
    }
  });

  group('caseSensitive', () {
    test('applies to names, globs, quoted phrases, and path:', () {
      expect(run('MAIN', caseSensitive: true), isEmpty);
      expect(run('Widget', caseSensitive: true), {'Widget.DART'});
      expect(run('widget', caseSensitive: true), isEmpty);
      expect(
        run('*.dart', caseSensitive: true),
        dartFiles.difference({'Widget.DART'}),
      );
      expect(run('"my notes"', caseSensitive: true), isEmpty);
      expect(run('"My Notes"', caseSensitive: true), {'My Notes.txt'});
      expect(run('path:LIB', caseSensitive: true), isEmpty);
      expect(run('path:docs/My', caseSensitive: true), {'My Notes.txt'});
    });

    test('does not apply to ext:, type:, or keys', () {
      expect(run('ext:dart', caseSensitive: true), dartFiles);
      expect(run('EXT:DART', caseSensitive: true), dartFiles);
      expect(run('TYPE:DIR', caseSensitive: true), dirs);
      expect(run('Path:lib/src', caseSensitive: true), {
        'src',
        'tree_query.dart',
        'Widget.DART',
      });
    });

    test('folds non-ASCII letters per character on every platform', () {
      final unicode = DirectoryTree<Never>.build(const [
        TreeEntry.file('/u/Ärger.txt'),
        TreeEntry.file('/u/ΟΔΟΣ.md'),
        TreeEntry.file('/u/odoς.md'),
        TreeEntry.file('/u/İstanbul.txt'),
        TreeEntry.file('/u/😀smile.txt'),
      ]);
      Set<String> names(String query) => {
        for (final node in unicode.nodes)
          if (TreeQuery.parse(query).matches(node)) node.name,
      };
      expect(names('ärger'), {'Ärger.txt'});
      expect(names('οδοσ'), {'ΟΔΟΣ.md'});
      expect(names('οδος'), {'ΟΔΟΣ.md'});
      // Final sigma and sigma fold together in both directions.
      expect(names('odoσ'), {'odoς.md'});
      // İ lowercases to two code units, so it is kept as is.
      expect(names('İstan'), {'İstanbul.txt'});
      expect(names('stanbul'), {'İstanbul.txt'});
      expect(names('?smile.txt'), {'😀smile.txt'});
      expect(names('😀*'), {'😀smile.txt'});
    });
  });

  group('matchesAll', () {
    for (final query in ['', ' ', '\t\n\r ', '　', '""', '!""', '"" ""']) {
      test('${_show(query)} has no terms', () {
        expect(TreeQuery.parse(query).matchesAll, isTrue);
        expect(TreeQuery.parse(query, caseSensitive: true).matchesAll, isTrue);
      });
    }

    for (final query in [
      'a',
      '*',
      '!',
      ' x ',
      'ext:dart',
      'type:',
      '!a',
      '"a',
    ]) {
      test('${_show(query)} has a term', () {
        expect(TreeQuery.parse(query).matchesAll, isFalse);
      });
    }
  });

  group('matchRanges', () {
    final cases = <(String, String, List<Range>)>[
      ('ab', 'xabyab', [(start: 1, end: 3), (start: 4, end: 6)]),
      ('aa', 'aaa', [(start: 0, end: 3)]),
      ('aa', 'aaaa', [(start: 0, end: 4)]),
      ('ab cd', 'abcd', [(start: 0, end: 4)]),
      ('cd ab', 'abcd', [(start: 0, end: 4)]),
      ('abc b', 'abc', [(start: 0, end: 3)]),
      ('b abc', 'xabcxb', [(start: 1, end: 4), (start: 5, end: 6)]),
      ('MAIN', 'Main.dart', [(start: 0, end: 4)]),
      ('"n.d"', 'main.dart', [(start: 3, end: 6)]),
      ('"my notes', 'My Notes.txt', [(start: 0, end: 8)]),
      ('weird!name', 'weird!name', [(start: 0, end: 10)]),
      ('!', 'a!b', [(start: 1, end: 2)]),
      ('foo:bar', 'foo:bar.txt', [(start: 0, end: 7)]),
      ('type:x', 'type:x', [(start: 0, end: 6)]),
      ('b', '😀b', [(start: 2, end: 3)]),
      ('stan', 'İstanbul', [(start: 1, end: 5)]),
      ('ä', 'ÄäÄ', [(start: 0, end: 3)]),
      ('zz', 'main.dart', []),
      ('main', '', []),
      ('', 'main', []),
      ('   ', 'main', []),
      ('!main', 'main', []),
      ('*.dart', 'main.dart', []),
      ('ma?n', 'main', []),
      ('ext:dart', 'main.dart', []),
      ('type:f', 'f', []),
      ('path:main', 'main', []),
      ('!main dart', 'main.dart', [(start: 5, end: 9)]),
    ];
    for (final (query, text, expected) in cases) {
      test('${_show(query)} in ${_show(text)}', () {
        expect(TreeQuery.parse(query).matchRanges(text), expected);
      });
    }

    test('respects caseSensitive', () {
      final query = TreeQuery.parse('Main', caseSensitive: true);
      expect(query.matchRanges('main Main MAIN'), [(start: 5, end: 9)]);
    });

    test('returns an unmodifiable list', () {
      final ranges = TreeQuery.parse('a').matchRanges('a');
      expect(() => ranges.add((start: 0, end: 1)), throwsUnsupportedError);
    });

    test('agrees with a brute-force oracle on random input', () {
      final random = Random(7);
      for (var round = 0; round < 2000; round++) {
        final words = [
          for (var w = random.nextInt(4); w > 0; w--)
            _randomString(random, 'aAb/', 1 + random.nextInt(3)),
        ];
        final caseSensitive = random.nextBool();
        final text = _randomString(random, 'aAbc/', random.nextInt(20));
        final query = TreeQuery.parse(
          words.join(' '),
          caseSensitive: caseSensitive,
        );
        final actual = query.matchRanges(text);

        final covered = List<bool>.filled(text.length, false);
        final haystack = caseSensitive ? text : text.toLowerCase();
        for (final word in words) {
          final needle = caseSensitive ? word : word.toLowerCase();
          for (var i = 0; i + needle.length <= haystack.length; i++) {
            if (haystack.substring(i, i + needle.length) == needle) {
              covered.fillRange(i, i + needle.length, true);
            }
          }
        }
        final expected = <Range>[];
        for (var i = 0; i < covered.length; i++) {
          if (!covered[i]) continue;
          var end = i;
          while (end < covered.length && covered[end]) {
            end++;
          }
          expected.add((start: i, end: end));
          i = end;
        }
        expect(actual, expected, reason: '${words.join(' ')} in $text');
      }
    });

    test('is non-empty for the name of every node a plain query matches', () {
      final random = Random(11);
      for (var round = 0; round < 500; round++) {
        final word = _randomString(random, 'aemdtr.', 1 + random.nextInt(2));
        final query = TreeQuery.parse(word);
        for (final node in tree.nodes) {
          expect(
            query.matchRanges(node.name).isNotEmpty,
            query.matches(node),
            reason: '$word on ${node.name}',
          );
        }
      }
    });
  });

  group('globs', () {
    test('agree with a regular-expression oracle', () {
      final random = Random(3);
      for (var round = 0; round < 5000; round++) {
        final pattern = _randomString(random, 'ab*?', 1 + random.nextInt(6));
        final name = _randomString(random, 'ab', 1 + random.nextInt(8));
        if (!pattern.contains('*') && !pattern.contains('?')) continue;
        final regex = RegExp(
          '^${pattern.split('').map((c) {
            if (c == '*') return '.*';
            if (c == '?') return '.';
            return RegExp.escape(c);
          }).join()}\$',
        );
        final glob = DirectoryTree<Never>.build([TreeEntry.file('/g/$name')]);
        final node = glob.nodeAt('/g/$name')!;
        expect(
          TreeQuery.parse(pattern).matches(node),
          regex.hasMatch(name),
          reason: '$pattern on $name',
        );
      }
    });

    test('do not backtrack exponentially on pathological patterns', () {
      final long = 'a' * 50000;
      final pathological = DirectoryTree<Never>.build([
        TreeEntry.file('/p/$long'),
        TreeEntry.file('/p/${long}b'),
      ]);
      final query = TreeQuery.parse('*a*a*a*a*a*a*a*a*a*a*a*a*b');
      final stopwatch = Stopwatch()..start();
      expect(
        [
          for (final node in pathological.nodes)
            if (query.matches(node)) node.name.length,
        ],
        [50001],
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('parse never throws', () {
    test('on random strings of syntax characters', () {
      const alphabet =
          '"!:*?\\/,. \t\n\r　 aAbB'
          'extypathfiledirmdÄİΣς';
      final random = Random(42);
      final nodes = tree.nodes;
      for (var round = 0; round < 5000; round++) {
        final source = _randomString(random, alphabet, random.nextInt(24));
        for (final caseSensitive in [false, true]) {
          final query = TreeQuery.parse(source, caseSensitive: caseSensitive);
          for (final node in nodes) {
            query.matches(node);
          }
          _checkRanges(query.matchRanges(source), source);
          expect(query.toString(), contains(source));
        }
      }
    });

    test('on random UTF-16 code units, including lone surrogates', () {
      final random = Random(99);
      for (var round = 0; round < 3000; round++) {
        final units = [
          for (var i = random.nextInt(16); i > 0; i--)
            random.nextBool()
                ? '"!: *?\t'.codeUnitAt(random.nextInt(7))
                : random.nextInt(0x10000),
        ];
        final source = String.fromCharCodes(units);
        final query = TreeQuery.parse(source);
        for (final node in tree.nodes) {
          query.matches(node);
        }
        _checkRanges(query.matchRanges(source), source);
      }
    });

    test('on very long and repetitive input', () {
      for (final source in [
        ':' * 100000,
        'a:' * 50000,
        '"' * 100001,
        '!' * 100000,
        '*' * 100000,
        'ext:${',' * 100000}',
      ]) {
        final query = TreeQuery.parse(source);
        for (final node in tree.nodes) {
          query.matches(node);
        }
      }
    });
  });

  group('terms with a separator', () {
    final project = DirectoryTree<Never>.build(const [
      TreeEntry.file('/r/lib/src/utils/a.dart'),
      TreeEntry.file('/r/lib/src/utils/gen/x.g.dart'),
      TreeEntry.file('/r/lib/src/b.dart'),
      TreeEntry.file('/r/lib/main.dart'),
      TreeEntry.file('/r/README.md'),
    ]);

    Set<String> paths(
      DirectoryTree<Object?> tree,
      String query, {
      bool caseSensitive = false,
    }) {
      final parsed = TreeQuery.parse(query, caseSensitive: caseSensitive);
      return {
        for (final node in tree.nodes)
          if (parsed.matches(node)) node.path.toString(),
      };
    }

    final cases = <String, Set<String>>{
      // The occurrence must reach the node's own name: end inside it or
      // exactly where it starts.
      'lib/src': {'/r/lib/src'},
      'src/ut': {'/r/lib/src/utils'},
      'lib/src/utils': {'/r/lib/src/utils'},
      'r/lib': {'/r/lib'},
      // '/r' also reaches into 'README.md' when case is ignored.
      '/r': {'/r', '/r/README.md'},
      '/r/': {'/r/lib', '/r/README.md'},
      '/': {
        '/r',
        '/r/lib',
        '/r/lib/src',
        '/r/lib/src/utils',
        '/r/lib/src/utils/a.dart',
        '/r/lib/src/utils/gen',
        '/r/lib/src/utils/gen/x.g.dart',
        '/r/lib/src/b.dart',
        '/r/lib/main.dart',
        '/r/README.md',
      },
      '/README': {'/r/README.md'},
      'utils/a': {'/r/lib/src/utils/a.dart'},
      'b/s': {'/r/lib/src'},
      // A trailing separator lists the folder's direct children.
      'lib/': {'/r/lib/src', '/r/lib/main.dart'},
      'lib/src/': {'/r/lib/src/utils', '/r/lib/src/b.dart'},
      'lib/src/utils/gen/': {'/r/lib/src/utils/gen/x.g.dart'},
      r'lib\': {'/r/lib/src', '/r/lib/main.dart'},
      'LIB/SRC/': {'/r/lib/src/utils', '/r/lib/src/b.dart'},
      'lib/ type:file': {'/r/lib/main.dart'},
      '!lib/ type:file': {
        '/r/lib/src/utils/a.dart',
        '/r/lib/src/utils/gen/x.g.dart',
        '/r/lib/src/b.dart',
        '/r/README.md',
      },
      'main.dart/': {},
      'nope/src': {},
      // Quoted phrases and backslashes.
      '"lib/src"': {'/r/lib/src'},
      r'lib\src': {'/r/lib/src'},
      r'"src\utils"': {'/r/lib/src/utils'},
      // Case folding.
      'LIB/SRC': {'/r/lib/src'},
      // AND with other terms.
      'lib/src type:file': {},
      'src/b ext:dart': {'/r/lib/src/b.dart'},
      // Negation.
      '!lib/src type:dir': {
        '/r',
        '/r/lib',
        '/r/lib/src/utils',
        '/r/lib/src/utils/gen',
      },
      // Globs match the last k path components.
      'src/*.dart': {'/r/lib/src/b.dart'},
      'src/**/*.dart': {'/r/lib/src/utils/a.dart'},
      '*/*.dart': {
        '/r/lib/src/utils/a.dart',
        '/r/lib/src/utils/gen/x.g.dart',
        '/r/lib/src/b.dart',
        '/r/lib/main.dart',
      },
      'utils/*/*.g.dart': {'/r/lib/src/utils/gen/x.g.dart'},
      '*/utils': {'/r/lib/src/utils'},
      'lib/s?c': {'/r/lib/src'},
      '/*': {'/r'},
      '/*/lib': {'/r/lib'},
      r'src\*.dart': {'/r/lib/src/b.dart'},
      'SRC/*.DART': {'/r/lib/src/b.dart'},
      '!*/*.dart type:file': {'/r/README.md'},
      'r/*/src/b.dart': {'/r/lib/src/b.dart'},
      'x/*/src/b.dart': {},
      // The path root's empty component counts, so `*` may match nothing.
      '*/r/lib/src/b.dart': {'/r/lib/src/b.dart'},
      '/r/lib/src/b.dart?': {},
    };
    for (final entry in cases.entries) {
      test('${_show(entry.key)} matches ${entry.value}', () {
        expect(paths(project, entry.key), entry.value);
      });
    }

    test('the class documentation examples hold', () {
      final docs = DirectoryTree.fromPaths([
        '/repo/lib/main.dart',
        '/repo/lib/main.g.dart',
        '/repo/README.md',
      ]);
      final query = TreeQuery.parse('ext:dart !*.g.dart');
      expect(docs.nodes.where(query.matches).map((n) => n.name), ['main.dart']);
      expect(TreeQuery.parse('MAIN').matchRanges('main.dart'), [
        (start: 0, end: 4),
      ]);
      expect(TreeQuery.parse('   ').matchesAll, isTrue);
      final lib = TreeQuery.parse('repo/lib');
      expect(docs.nodes.where(lib.matches).map((n) => n.name), ['lib']);
      expect(lib.matchRanges('repo/lib'), [(start: 0, end: 8)]);
      final contents = TreeQuery.parse('repo/lib/');
      expect(docs.nodes.where(contents.matches).map((n) => n.name), [
        'main.dart',
        'main.g.dart',
      ]);
      final generated = TreeQuery.parse('lib/*.g.dart');
      expect(docs.nodes.where(generated.matches).map((n) => n.name), [
        'main.g.dart',
      ]);
    });

    test('path-root nodes are all name for terms with a separator', () {
      final roots = DirectoryTree<Never>.build(const [
        TreeEntry.file('/a/x.txt'),
        TreeEntry.file(r'C:\b\y.txt'),
        TreeEntry.file(r'\\srv\share\c\z.txt'),
      ], options: const TreeOptions(roots: TreeRoots.filesystem()));
      expect(
        roots.nodes.where((node) => node.path.isRoot).map((n) => n.name),
        unorderedEquals(['/', 'C:', '//srv/share']),
      );
      final cases = <String, Set<String>>{
        // An occurrence that starts at the first character of a path root
        // reaches its name, whatever the root's shape.
        'c:/': {'C:/', 'C:/b'},
        'C:/B': {'C:/b'},
        '//srv/': {'//srv/share/'},
        '//srv/share/': {'//srv/share/', '//srv/share/c'},
        'srv/share': {'//srv/share/'},
        // A separator alone reaches every name after a separator, and the
        // POSIX root, whose name is the separator.
        '/': {
          '/',
          '/a',
          '/a/x.txt',
          'C:/',
          'C:/b',
          'C:/b/y.txt',
          '//srv/share/',
          '//srv/share/c',
          '//srv/share/c/z.txt',
        },
      };
      for (final MapEntry(key: query, value: expected) in cases.entries) {
        expect(paths(roots, query), expected, reason: query);
      }
      expect(paths(roots, 'C:/', caseSensitive: true), {'C:/', 'C:/b'});
      expect(paths(roots, 'c:/', caseSensitive: true), isEmpty);
    });

    test('typing a path character by character never empties the view', () {
      final typed = DirectoryTree<Never>.build(const [
        TreeEntry.file('/r/lib/src/a.dart'),
        TreeEntry.file('/r/README.md'),
      ]);
      const steps = ['l', 'li', 'lib', 'lib/', 'lib/s', 'lib/src', 'lib/src/'];
      const expected = <String, Set<String>>{
        'l': {'/r/lib'},
        'li': {'/r/lib'},
        'lib': {'/r/lib'},
        'lib/': {'/r/lib/src'},
        'lib/s': {'/r/lib/src'},
        'lib/src': {'/r/lib/src'},
        'lib/src/': {'/r/lib/src/a.dart'},
      };
      for (final step in steps) {
        expect(paths(typed, step), expected[step], reason: step);
        for (final caseSensitive in [false, true]) {
          final rows = typed.flatten(
            filter: TreeQuery.parse(step, caseSensitive: caseSensitive),
          );
          expect(rows, isNotEmpty, reason: step);
          expect(
            rows.map((row) => row.node.path.toString()),
            containsAll(expected[step]!),
            reason: step,
          );
        }
      }
    });

    test('case sensitivity applies to fragments and segment globs', () {
      expect(paths(project, 'LIB/SRC', caseSensitive: true), isEmpty);
      expect(paths(project, 'lib/src', caseSensitive: true), {'/r/lib/src'});
      expect(paths(project, 'SRC/*.dart', caseSensitive: true), isEmpty);
      expect(paths(project, 'src/*.dart', caseSensitive: true), {
        '/r/lib/src/b.dart',
      });
    });

    test('typing a compacted row label finds that row', () {
      final deeper = DirectoryTree<Never>.build(const [
        TreeEntry.file('/r/lib/src/utils/a.dart'),
        TreeEntry.file('/r/lib/src/utils/b.dart'),
        TreeEntry.file('/r/README.md'),
      ]);
      final compacted = deeper
          .flatten(compactFolders: true)
          .firstWhere((row) => row.label.contains('/'));
      expect(compacted.label, 'lib/src/utils');
      expect(compacted.node.path.toString(), '/r/lib/src/utils');
      for (final typed in ['lib/src/utils', 'src/utils', 'b/src/u', 'c/ut']) {
        final query = TreeQuery.parse(typed);
        expect(query.matches(compacted.node), isTrue, reason: typed);
        expect(query.matchRanges(compacted.label), isNotEmpty, reason: typed);
      }
      // A prefix of the label matches a chain member, which the view folds
      // into the same row.
      expect(paths(deeper, 'lib/src'), {'/r/lib/src'});
      expect(paths(deeper, 'src/ut'), {'/r/lib/src/utils'});
      for (final typed in ['lib/src', 'src/ut', 'lib/src/utils']) {
        final filtered = deeper.flatten(
          filter: TreeQuery.parse(typed),
          compactFolders: true,
        );
        expect(
          [for (final row in filtered) row.label],
          contains('lib/src/utils'),
          reason: typed,
        );
      }
    });

    test('typing a disambiguated top-level label finds that node', () {
      final twins = DirectoryTree<Never>.build(const [
        TreeEntry.file('/x/a/src/f.txt'),
        TreeEntry.file('/y/b/src/g.txt'),
      ]);
      final labels = [for (final node in twins.nodes) node.label];
      expect(labels, containsAll(['a/src', 'b/src']));
      expect(paths(twins, 'a/src'), {'/x/a/src'});
      expect(paths(twins, 'B/SRC'), {'/y/b/src'});
      expect(paths(twins, 'src/f'), {'/x/a/src/f.txt'});
      expect(TreeQuery.parse('a/src').matchRanges('a/src'), [
        (start: 0, end: 5),
      ]);
    });

    test('Windows-style input', () {
      final windows = DirectoryTree<Never>.build(const [
        TreeEntry.file(r'C:\Proj\Lib\Src\X.dart'),
        TreeEntry.file(r'C:\Proj\Lib\y.dart'),
      ]);
      expect(paths(windows, r'lib\src'), {'C:/Proj/Lib/Src'});
      expect(paths(windows, r'Lib\Src', caseSensitive: true), {
        'C:/Proj/Lib/Src',
      });
      expect(paths(windows, r'lib\src', caseSensitive: true), isEmpty);
      expect(paths(windows, r'src\x.'), {'C:/Proj/Lib/Src/X.dart'});
      expect(paths(windows, r'c:\proj\lib'), {'C:/Proj/Lib'});
      expect(paths(windows, r'lib\*.dart'), {'C:/Proj/Lib/y.dart'});
      expect(
        paths(windows, r'!lib\src type:dir'),
        isNot(contains('C:/Proj/Lib/Src')),
      );
      expect(TreeQuery.parse(r'lib\src').matchRanges('Lib/Src'), [
        (start: 0, end: 7),
      ]);
    });

    test(
      'a backslash name still matches literally when it is no separator',
      () {
        final posix = DirectoryTree<Never>.build(
          const [TreeEntry.file(r'/r/a\b.txt')],
          options: const TreeOptions(
            paths: PathPolicy(backslashIsSeparator: false),
          ),
        );
        expect(paths(posix, r'a\b'), {r'/r/a\b.txt'});
        expect(paths(posix, r'a\*.txt'), {r'/r/a\b.txt'});
        expect(TreeQuery.parse(r'a\b').matchRanges(r'a\b.txt'), [
          (start: 0, end: 3),
        ]);
      },
    );

    test('matchRanges highlights fragments in labels but not globs', () {
      expect(TreeQuery.parse('lib/src').matchRanges('lib/src/utils'), [
        (start: 0, end: 7),
      ]);
      expect(TreeQuery.parse('src/ut').matchRanges('lib/src/utils'), [
        (start: 4, end: 10),
      ]);
      expect(TreeQuery.parse('lib/src utils').matchRanges('lib/src/utils'), [
        (start: 0, end: 7),
        (start: 8, end: 13),
      ]);
      expect(TreeQuery.parse('lib/ /src').matchRanges('lib/src'), [
        (start: 0, end: 7),
      ]);
      expect(TreeQuery.parse('!lib/src').matchRanges('lib/src'), isEmpty);
      expect(TreeQuery.parse('src/*').matchRanges('src/a'), isEmpty);
    });

    test('agrees with a brute-force oracle on random trees', () {
      final random = Random(2024);
      for (var round = 0; round < 300; round++) {
        final entries = <TreeEntry<Never>>[
          for (var i = 1 + random.nextInt(8); i > 0; i--)
            TreeEntry.file(
              '/${[for (var d = 1 + random.nextInt(4); d > 0; d--) _randomString(random, 'aAb', 1 + random.nextInt(2))].join('/')}',
            ),
        ];
        final tree = DirectoryTree<Never>.build(entries);
        for (var q = 0; q < 10; q++) {
          final term = random.nextBool()
              ? _randomString(random, 'aB/*?', 2 + random.nextInt(6))
              : _randomString(random, 'aAb/', 2 + random.nextInt(6));
          if (!term.contains('/')) continue;
          final caseSensitive = random.nextBool();
          final query = TreeQuery.parse(term, caseSensitive: caseSensitive);
          for (final node in tree.nodes) {
            expect(
              query.matches(node),
              _oracle(node, term, caseSensitive: caseSensitive),
              reason: '$term on ${node.path} (caseSensitive: $caseSensitive)',
            );
          }
        }
      }
    });

    test('segment globs do not backtrack exponentially', () {
      final long = 'a' * 20000;
      final deep = DirectoryTree<Never>.build([
        TreeEntry.file('/$long/$long/${long}b'),
      ]);
      final query = TreeQuery.parse('*a*a*a*a*/*a*a*a*a*/*a*a*a*a*a*c');
      final stopwatch = Stopwatch()..start();
      expect(deep.nodes.where(query.matches), isEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('optimized matcher', () {
    // Letters chosen to hit every fold path: ASCII of both cases, Latin-1,
    // the Kelvin sign (folds to ASCII 'k'), dotted capital I (kept because
    // its lowercase is longer), Greek sigmas, an astral emoji, and the
    // characters around A-Z.
    const letters = [
      'a', 'A', 'b', 'B', 'k', 'K', '\u212A', 'i', 'I', 'İ', //
      'ä', 'Ä', 'σ', 'Σ', 'ς', 'ß', //
      '\u{1F600}', '_', '-', '.', 'x', 'X', ' ', //
      // The edges of the A-Z fold range.
      '@', 'Z', '[', '`', 'z', '{',
    ];
    String word(Random random, int maxLength) {
      final buffer = StringBuffer();
      for (var i = 1 + random.nextInt(maxLength); i > 0; i--) {
        buffer.write(letters[random.nextInt(letters.length)]);
      }
      return buffer.toString();
    }

    DirectoryTree<Never> randomTree(Random random) {
      final windows = random.nextInt(4) == 0;
      final separator = windows ? r'\' : '/';
      final entries = <TreeEntry<Never>>[
        for (var e = 1 + random.nextInt(10); e > 0; e--)
          (random.nextInt(4) == 0
              ? TreeEntry<Never>.directory
              : TreeEntry<Never>.file)(
            '${windows ? 'C:' : ''}$separator'
            '${[for (var d = 1 + random.nextInt(4); d > 0; d--) word(random, 6)].join(separator)}',
          ),
      ];
      return DirectoryTree<Never>.build(
        entries,
        options: TreeOptions(
          paths: random.nextBool()
              ? const PathPolicy()
              : PathPolicy.caseInsensitive,
        ),
      );
    }

    String randomQuery(Random random) {
      const pieces = [
        'ext:', 'EXT:', 'type:f', 'type:dir', 'path:', '!', '"', '*', '?', //
        '/', r'\', ',', '.', ' ', '\t', '**', ':',
      ];
      final buffer = StringBuffer();
      for (var i = 1 + random.nextInt(6); i > 0; i--) {
        if (random.nextInt(3) == 0) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        } else {
          buffer.write(word(random, 4));
        }
        if (random.nextInt(3) == 0) buffer.write(' ');
      }
      return buffer.toString();
    }

    test('agrees with the previous implementation on random input', () {
      final random = Random(515);
      var compared = 0;
      var matched = 0;
      for (var round = 0; round < 400; round++) {
        final tree = randomTree(random);
        for (var q = 0; q < 25; q++) {
          final source = randomQuery(random);
          for (final caseSensitive in [false, true]) {
            final query = TreeQuery.parse(source, caseSensitive: caseSensitive);
            final oracle = OldTreeQuery.parse(
              source,
              caseSensitive: caseSensitive,
            );
            expect(query.matchesAll, oracle.matchesAll, reason: source);
            for (final node in tree.nodes) {
              final expected = oracle.matches(node);
              expect(
                query.matches(node),
                expected,
                reason:
                    '${_show(source)} on ${node.path} '
                    '(caseSensitive: $caseSensitive)',
              );
              compared++;
              if (expected) matched++;
            }
            final label = tree.nodes.isEmpty ? source : tree.nodes.last.label;
            expect(
              query.matchRanges(label),
              oracle.matchRanges(label),
              reason: source,
            );
          }
        }
      }
      // Guard against a generator that only ever produces misses.
      expect(compared, greaterThan(50000));
      expect(matched, greaterThan(compared ~/ 50));
    });

    test('agrees on terms built from the node names themselves', () {
      final random = Random(616);
      for (var round = 0; round < 300; round++) {
        final tree = randomTree(random);
        final nodes = tree.nodes;
        if (nodes.isEmpty) continue;
        for (var q = 0; q < 10; q++) {
          // A slice of a real path, so plain, path, and glob terms hit.
          final path = nodes[random.nextInt(nodes.length)].path.toString();
          final from = random.nextInt(path.length);
          final to = from + 1 + random.nextInt(path.length - from);
          var term = path.substring(from, to).replaceAll(' ', '?');
          if (random.nextInt(3) == 0) term = '*$term';
          if (random.nextInt(4) == 0) term = term.toUpperCase();
          if (random.nextInt(5) == 0) term = '!$term';
          if (random.nextInt(5) == 0) term = 'path:$term';
          for (final caseSensitive in [false, true]) {
            final query = TreeQuery.parse(term, caseSensitive: caseSensitive);
            final oracle = OldTreeQuery.parse(
              term,
              caseSensitive: caseSensitive,
            );
            for (final node in nodes) {
              expect(
                query.matches(node),
                oracle.matches(node),
                reason:
                    '${_show(term)} on ${node.path} '
                    '(caseSensitive: $caseSensitive)',
              );
            }
          }
        }
      }
    });

    test('tests cheap terms first without changing results', () {
      // A counting filter cannot observe TreeQuery's own term order, so
      // check that reordering terms never changes a result instead.
      final random = Random(717);
      for (var round = 0; round < 200; round++) {
        final tree = randomTree(random);
        final terms = [
          for (var i = 2 + random.nextInt(3); i > 0; i--)
            randomQuery(random).trim(),
        ]..removeWhere((term) => term.isEmpty);
        final forward = TreeQuery.parse(terms.join(' '));
        final backward = TreeQuery.parse(terms.reversed.join(' '));
        for (final node in tree.nodes) {
          expect(
            forward.matches(node),
            backward.matches(node),
            reason: '$terms',
          );
        }
      }
    });

    test('the Kelvin sign folds to k in names and paths', () {
      final kelvin = DirectoryTree<Never>.build(const [
        TreeEntry.file('/r/\u212Aelvin/\u212Ab.txt'),
        TreeEntry.file('/r/plain/kb.txt'),
      ]);
      Set<String> paths(String source, {bool caseSensitive = false}) {
        final query = TreeQuery.parse(source, caseSensitive: caseSensitive);
        return {
          for (final node in kelvin.nodes)
            if (query.matches(node)) node.path.toString(),
        };
      }

      expect(paths('kb'), {'/r/\u212Aelvin/\u212Ab.txt', '/r/plain/kb.txt'});
      expect(paths('kb', caseSensitive: true), {'/r/plain/kb.txt'});
      expect(paths('kelvin/k'), {'/r/\u212Aelvin/\u212Ab.txt'});
      expect(paths('k?.txt'), {
        '/r/\u212Aelvin/\u212Ab.txt',
        '/r/plain/kb.txt',
      });
      expect(paths('kelvin/*.txt'), {'/r/\u212Aelvin/\u212Ab.txt'});
      expect(paths('path:/kelvin'), {
        '/r/\u212Aelvin',
        '/r/\u212Aelvin/\u212Ab.txt',
      });
    });
  });

  group('value semantics', () {
    test('equality and hashCode use source and caseSensitive', () {
      final a = TreeQuery.parse('ext:dart main');
      final b = TreeQuery.parse('ext:dart main');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(TreeQuery.parse('ext:dart main', caseSensitive: true)));
      expect(a, isNot(TreeQuery.parse('ext:dart  main')));
      expect(a.source, 'ext:dart main');
      expect(a.caseSensitive, isFalse);
    });

    test('toString shows the source', () {
      expect(TreeQuery.parse('ext:dart').toString(), "TreeQuery('ext:dart')");
      expect(
        TreeQuery.parse('A', caseSensitive: true).toString(),
        "TreeQuery('A', caseSensitive)",
      );
    });
  });

  group('composition', () {
    final mainDart = tree.nodeAt('/repo/lib/main.dart')!;
    final readme = tree.nodeAt('/repo/README.md')!;

    test('and, or, and negate combine with other filters', () {
      final dart = TreeQuery.parse('ext:dart');
      final main = TreeFilter.where<Object?>(
        (node) => node.name == 'main.dart',
      );
      expect(dart.and(main).matches(mainDart), isTrue);
      expect(dart.and(main).matches(readme), isFalse);
      expect(dart.or(TreeQuery.parse('readme')).matches(readme), isTrue);
      expect(dart.negate().matches(readme), isTrue);
      expect(dart.negate().matches(mainDart), isFalse);
    });

    test('matchesAll propagates through combinators', () {
      final empty = TreeQuery.parse(' ');
      final some = TreeQuery.parse('x');
      expect(empty.and(empty).matchesAll, isTrue);
      expect(empty.and(some).matchesAll, isFalse);
      expect(empty.or(some).matchesAll, isTrue);
      expect(empty.negate().matchesAll, isFalse);
      expect(empty.negate().matches(mainDart), isFalse);
    });
  });
}

String _randomString(Random random, String alphabet, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// Checks the matchRanges invariants: in bounds, non-empty, sorted, and
/// neither overlapping nor touching.
void _checkRanges(List<Range> ranges, String text) {
  var previousEnd = -1;
  for (final range in ranges) {
    expect(range.start, greaterThanOrEqualTo(0));
    expect(range.end, lessThanOrEqualTo(text.length));
    expect(range.start, lessThan(range.end));
    expect(range.start, greaterThan(previousEnd));
    previousEnd = range.end;
  }
}

/// Spec oracle for a term containing '/': for a plain term, a literal name
/// match or an occurrence in the path string that ends at or after the
/// start of the name (checked at every index); for a glob, a regular
/// expression over the name or over the last k components of the path
/// string.
bool _oracle(
  TreeNode<Object?> node,
  String term, {
  required bool caseSensitive,
}) {
  String fold(String s) => caseSensitive ? s : s.toLowerCase();
  final name = fold(node.name);
  final path = fold(node.path.toString());
  final t = fold(term);
  if (t.contains('*') || t.contains('?')) {
    bool whole(String pattern, String subject) => RegExp(
      '^${pattern.split('').map((c) {
        if (c == '*') return '.*';
        if (c == '?') return '.';
        return RegExp.escape(c);
      }).join()}\$',
    ).hasMatch(subject);
    final k = t.split('/').length;
    final parts = path.split('/');
    final tail = parts.sublist(max(0, parts.length - k)).join('/');
    return whole(t, name) || whole(t, tail);
  }
  if (name.contains(t)) return true;
  final nameStart = node.path.segments.isEmpty ? 0 : path.length - name.length;
  for (var i = 0; i + t.length <= path.length; i++) {
    if (path.startsWith(t, i) && i + t.length >= nameStart) return true;
  }
  return false;
}

String _show(String text) =>
    "'${text.replaceAll('\t', r'\t').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";

// ---------------------------------------------------------------------------
// Oracle: TreeQuery as of commit 25f9c0d, before matches became
// allocation-free. Copied verbatim except for the class name, imports, and
// doc comments; the property test above checks the optimized matcher
// against it.
// ---------------------------------------------------------------------------

final class OldTreeQuery extends TreeFilter {
  OldTreeQuery._(
    this.source,
    this.caseSensitive,
    this._terms,
    this._highlights,
  );

  factory OldTreeQuery.parse(String query, {bool caseSensitive = false}) {
    final terms = _Parser(query, caseSensitive: caseSensitive).parse();
    final highlights = <String>[
      for (final term in terms)
        if (!term.negated && term is _TextTerm) ...term.highlights,
    ];
    return OldTreeQuery._(
      query,
      caseSensitive,
      List<_Term>.unmodifiable(terms),
      List<String>.unmodifiable(highlights),
    );
  }

  final String source;

  final bool caseSensitive;

  final List<_Term> _terms;

  final List<String> _highlights;

  @override
  bool get matchesAll => _terms.isEmpty;

  @override
  bool matches(TreeNode<Object?> node) {
    if (_terms.isEmpty) return true;
    final subject = _Subject(node, caseSensitive: caseSensitive);
    for (final term in _terms) {
      if (term.test(subject) == term.negated) return false;
    }
    return true;
  }

  List<({int start, int end})> matchRanges(String text) {
    if (_highlights.isEmpty || text.isEmpty) {
      return const <({int start, int end})>[];
    }
    final haystack = caseSensitive ? text : _fold(text);
    final found = <({int start, int end})>[];
    for (final needle in _highlights) {
      var index = haystack.indexOf(needle);
      while (index >= 0) {
        found.add((start: index, end: index + needle.length));
        index = haystack.indexOf(needle, index + 1);
      }
    }
    if (found.isEmpty) return const <({int start, int end})>[];
    found.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
    final merged = <({int start, int end})>[];
    var start = found.first.start;
    var end = found.first.end;
    for (var i = 1; i < found.length; i++) {
      final range = found[i];
      if (range.start <= end) {
        if (range.end > end) end = range.end;
      } else {
        merged.add((start: start, end: end));
        start = range.start;
        end = range.end;
      }
    }
    merged.add((start: start, end: end));
    return List<({int start, int end})>.unmodifiable(merged);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OldTreeQuery &&
          other.source == source &&
          other.caseSensitive == caseSensitive;

  @override
  int get hashCode => Object.hash(OldTreeQuery, source, caseSensitive);

  @override
  String toString() => caseSensitive
      ? "OldTreeQuery('$source', caseSensitive)"
      : "OldTreeQuery('$source')";
}

// ---------------------------------------------------------------------------
// Terms
// ---------------------------------------------------------------------------

final class _Subject {
  _Subject(this.node, {required this.caseSensitive});

  final TreeNode<Object?> node;
  final bool caseSensitive;

  late final String name = caseSensitive ? node.name : _fold(node.name);

  late final List<int> nameRunes = name.runes.toList(growable: false);

  late final String foldedName = caseSensitive ? _fold(node.name) : name;

  late final String path = caseSensitive
      ? node.path.toString()
      : _fold(node.path.toString());

  late final int nameStart = node.path.segments.isEmpty
      ? 0
      : path.length - node.path.segments.last.length;

  List<int> tailRunes(int count) {
    var start = 0;
    var seen = 0;
    for (var i = path.length - 1; i >= 0; i--) {
      if (path.codeUnitAt(i) == _slash && ++seen == count) {
        start = i + 1;
        break;
      }
    }
    return path.substring(start).runes.toList(growable: false);
  }
}

sealed class _Term {
  _Term({required this.negated});

  final bool negated;

  bool test(_Subject subject);
}

final class _TextTerm extends _Term {
  _TextTerm(this.text, this.segmentText, {required super.negated});

  final String text;

  final String? segmentText;

  List<String> get highlights {
    final segment = segmentText;
    return segment == null || segment == text ? [text] : [text, segment];
  }

  @override
  bool test(_Subject subject) {
    if (subject.name.contains(text)) return true;
    final segment = segmentText;
    if (segment == null) return false;
    // The last occurrence ends furthest right, so it is the only one that
    // needs checking: it reaches the name if any occurrence does.
    final index = subject.path.lastIndexOf(segment);
    return index >= 0 && index + segment.length >= subject.nameStart;
  }
}

final class _GlobTerm extends _Term {
  _GlobTerm(
    this.pattern,
    this.segmentPattern,
    this.segmentCount, {
    required super.negated,
  });

  final List<int> pattern;

  final List<int>? segmentPattern;

  final int segmentCount;

  @override
  bool test(_Subject subject) {
    if (_globMatches(pattern, subject.nameRunes)) return true;
    final segments = segmentPattern;
    return segments != null &&
        _globMatches(segments, subject.tailRunes(segmentCount));
  }
}

final class _ExtTerm extends _Term {
  _ExtTerm(this.suffixes, {required super.negated});

  final List<String> suffixes;

  @override
  bool test(_Subject subject) {
    if (!subject.node.isFile) return false;
    final name = subject.foldedName;
    for (final suffix in suffixes) {
      if (name.length > suffix.length && name.endsWith(suffix)) return true;
    }
    return false;
  }
}

final class _TypeTerm extends _Term {
  _TypeTerm({required super.negated, required this.directory});

  final bool directory;

  @override
  bool test(_Subject subject) => subject.node.isDirectory == directory;
}

final class _PathTerm extends _Term {
  _PathTerm(this.text, {required super.negated});

  final String text;

  @override
  bool test(_Subject subject) => subject.path.contains(text);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const int _quote = 0x22; // "
const int _bang = 0x21; // !
const int _colon = 0x3A; // :
const int _star = 0x2A; // *
const int _question = 0x3F; // ?
const int _slash = 0x2F; // /

final class _Parser {
  _Parser(this.source, {required this.caseSensitive});

  final String source;
  final bool caseSensitive;
  final List<_Term> terms = <_Term>[];
  int index = 0;

  List<_Term> parse() {
    final length = source.length;
    while (true) {
      while (index < length && _isWhitespace(source.codeUnitAt(index))) {
        index++;
      }
      if (index >= length) break;
      _parseTerm();
    }
    return terms;
  }

  void _parseTerm() {
    final length = source.length;
    var negated = false;
    if (source.codeUnitAt(index) == _bang &&
        index + 1 < length &&
        !_isWhitespace(source.codeUnitAt(index + 1))) {
      negated = true;
      index++;
    }
    if (source.codeUnitAt(index) == _quote) {
      final phrase = _readQuoted();
      if (phrase.isNotEmpty) terms.add(_textTerm(phrase, negated: negated));
      return;
    }
    // A bare word runs to the next whitespace. Quotes inside it are literal,
    // except right after a known key. Only the first colon can end a key.
    final start = index;
    var sawColon = false;
    while (index < length && !_isWhitespace(source.codeUnitAt(index))) {
      if (!sawColon && source.codeUnitAt(index) == _colon) {
        sawColon = true;
        final key = _keyOf(source.substring(start, index));
        if (key != null) {
          index++;
          _parseKeyValue(key, start, negated: negated);
          return;
        }
      }
      index++;
    }
    _addPlain(source.substring(start, index), negated: negated);
  }

  void _parseKeyValue(String key, int start, {required bool negated}) {
    final length = source.length;
    String value;
    if (index < length && source.codeUnitAt(index) == _quote) {
      value = _readQuoted();
    } else {
      final valueStart = index;
      while (index < length && !_isWhitespace(source.codeUnitAt(index))) {
        index++;
      }
      value = source.substring(valueStart, index);
    }
    final term = _keyTerm(key, value, negated: negated);
    if (term != null) {
      terms.add(term);
    } else {
      // Not a usable key term: the whole spelling, quotes included, is
      // searched for literally.
      _addPlain(source.substring(start, index), negated: negated);
    }
  }

  String _readQuoted() {
    final contentStart = index + 1;
    final close = source.indexOf('"', contentStart);
    if (close < 0) {
      index = source.length;
      return source.substring(contentStart);
    }
    index = close + 1;
    return source.substring(contentStart, close);
  }

  void _addPlain(String text, {required bool negated}) {
    // Callers only pass non-empty words, but stay defensive.
    if (text.isEmpty) return;
    if (!text.contains('*') && !text.contains('?')) {
      terms.add(_textTerm(text, negated: negated));
      return;
    }
    final folded = _caseFold(text);
    List<int>? segmentPattern;
    var segmentCount = 0;
    if (_hasSeparator(folded)) {
      final normalized = folded.replaceAll(r'\', '/');
      segmentPattern = _compileGlob(normalized);
      segmentCount = '/'.allMatches(normalized).length + 1;
    }
    terms.add(
      _GlobTerm(
        _compileGlob(folded),
        segmentPattern,
        segmentCount,
        negated: negated,
      ),
    );
  }

  _TextTerm _textTerm(String text, {required bool negated}) {
    final folded = _caseFold(text);
    return _TextTerm(
      folded,
      _hasSeparator(folded) ? folded.replaceAll(r'\', '/') : null,
      negated: negated,
    );
  }

  static bool _hasSeparator(String text) =>
      text.contains('/') || text.contains(r'\');

  _Term? _keyTerm(String key, String value, {required bool negated}) {
    if (value.isEmpty) return null;
    switch (key) {
      case 'ext':
        final suffixes = <String>[];
        for (var part in value.split(',')) {
          if (part.startsWith('.')) part = part.substring(1);
          if (part.isEmpty) continue;
          final suffix = '.${_fold(part)}';
          if (!suffixes.contains(suffix)) suffixes.add(suffix);
        }
        if (suffixes.isEmpty) return null;
        return _ExtTerm(List<String>.unmodifiable(suffixes), negated: negated);
      case 'type':
        switch (_fold(value)) {
          case 'file':
          case 'f':
            return _TypeTerm(negated: negated, directory: false);
          case 'dir':
          case 'directory':
          case 'd':
            return _TypeTerm(negated: negated, directory: true);
        }
        return null;
      case 'path':
        return _PathTerm(
          _caseFold(value.replaceAll(r'\', '/')),
          negated: negated,
        );
    }
    return null;
  }

  String _caseFold(String text) => caseSensitive ? text : _fold(text);

  static String? _keyOf(String word) {
    if (word.length > 4) return null;
    switch (_fold(word)) {
      case 'ext':
        return 'ext';
      case 'type':
        return 'type';
      case 'path':
        return 'path';
    }
    return null;
  }
}

List<int> _compileGlob(String glob) {
  final pattern = <int>[];
  for (final rune in glob.runes) {
    if (rune == _star && pattern.isNotEmpty && pattern.last == _star) continue;
    pattern.add(rune);
  }
  return List<int>.unmodifiable(pattern);
}

bool _globMatches(List<int> pattern, List<int> name) {
  var p = 0;
  var n = 0;
  var star = -1;
  var resume = 0;
  while (n < name.length) {
    if (p < pattern.length &&
        pattern[p] != _star &&
        (pattern[p] == _question || pattern[p] == name[n])) {
      p++;
      n++;
    } else if (p < pattern.length && pattern[p] == _star) {
      star = p;
      p++;
      resume = n;
    } else if (star >= 0) {
      p = star + 1;
      resume++;
      n = resume;
    } else {
      return false;
    }
  }
  while (p < pattern.length && pattern[p] == _star) {
    p++;
  }
  return p == pattern.length;
}

String _fold(String text) {
  var ascii = true;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) > 0x7F) {
      ascii = false;
      break;
    }
  }
  if (ascii) return text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune < 0x80) {
      buffer.writeCharCode(rune >= 0x41 && rune <= 0x5A ? rune + 0x20 : rune);
      continue;
    }
    if (rune == 0x3C2) {
      buffer.writeCharCode(0x3C3);
      continue;
    }
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    buffer.write(lower.length == char.length ? lower : char);
  }
  return buffer.toString();
}

bool _isWhitespace(int unit) {
  if (unit <= 0x20) {
    return unit == 0x20 || (unit >= 0x09 && unit <= 0x0D);
  }
  if (unit < 0x85) return false;
  return unit == 0x85 ||
      unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000 ||
      unit == 0xFEFF;
}
