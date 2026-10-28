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
      // The occurrence must reach into the node's own name.
      'lib/src': {'/r/lib/src'},
      'src/ut': {'/r/lib/src/utils'},
      'lib/src/utils': {'/r/lib/src/utils'},
      'r/lib': {'/r/lib'},
      // '/r' also reaches into 'README.md' when case is ignored.
      '/r': {'/r', '/r/README.md'},
      '/r/': {},
      '/README': {'/r/README.md'},
      'utils/a': {'/r/lib/src/utils/a.dart'},
      'b/s': {'/r/lib/src'},
      'lib/': {},
      'lib/src/': {},
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
      final generated = TreeQuery.parse('lib/*.g.dart');
      expect(docs.nodes.where(generated.matches).map((n) => n.name), [
        'main.g.dart',
      ]);
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
/// match or an occurrence in the path string that ends after the name
/// starts (checked at every index); for a glob, a regular expression over
/// the name or over the last k components of the path string.
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
    if (path.startsWith(t, i) && i + t.length > nameStart) return true;
  }
  return false;
}

String _show(String text) =>
    "'${text.replaceAll('\t', r'\t').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";
