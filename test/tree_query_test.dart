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
            _randomString(random, 'aAb', 1 + random.nextInt(3)),
        ];
        final caseSensitive = random.nextBool();
        final text = _randomString(random, 'aAbc', random.nextInt(20));
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

String _show(String text) =>
    "'${text.replaceAll('\t', r'\t').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";
