import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

/// The canonical string, computed independently from root and segments.
String canonicalOracle(TreePath path) {
  final segments = path.segments;
  if (segments.isEmpty) return path.root.isEmpty ? '.' : path.root;
  final first = segments.first;
  final driveLike =
      first.length == 2 &&
      first[1] == ':' &&
      RegExp('[A-Za-z]').hasMatch(first[0]);
  final prefix = path.root.isEmpty && driveLike ? './' : path.root;
  return '$prefix${segments.join('/')}';
}

void main() {
  group('TreePath.parse', () {
    // input -> (root, segments, canonical string)
    final table = <String, (String, List<String>, String)>{
      // POSIX
      '/': ('/', [], '/'),
      '/a': ('/', ['a'], '/a'),
      '/a/b/c.txt': ('/', ['a', 'b', 'c.txt'], '/a/b/c.txt'),
      '/a/': ('/', ['a'], '/a'),
      '//': ('/', [], '/'),
      '///a//b': ('/', ['a', 'b'], '/a/b'),
      '////srv/share': ('/', ['srv', 'share'], '/srv/share'),
      '/./a/../b': ('/', ['b'], '/b'),
      '/..': ('/', [], '/'),
      '/../a': ('/', ['a'], '/a'),
      '/C:/x': ('/', ['C:', 'x'], '/C:/x'),
      // Relative
      'a': ('', ['a'], 'a'),
      'a/b/': ('', ['a', 'b'], 'a/b'),
      '.': ('', [], '.'),
      './': ('', [], '.'),
      'a/..': ('', [], '.'),
      './a/./b': ('', ['a', 'b'], 'a/b'),
      'a/../b': ('', ['b'], 'b'),
      ' a ': ('', [' a '], ' a '),
      'C:foo': ('', ['C:foo'], 'C:foo'),
      'c:foo/bar': ('', ['c:foo', 'bar'], 'c:foo/bar'),
      'a/../C:/x': ('', ['C:', 'x'], './C:/x'),
      './c:': ('', ['c:'], './c:'),
      // Drives: the letter is always uppercased.
      'C:': ('C:/', [], 'C:/'),
      'c:': ('C:/', [], 'C:/'),
      'C:/': ('C:/', [], 'C:/'),
      r'C:\': ('C:/', [], 'C:/'),
      r'c:\a\b': ('C:/', ['a', 'b'], 'C:/a/b'),
      'c:/a': ('C:/', ['a'], 'C:/a'),
      r'C:\a/b\c\': ('C:/', ['a', 'b', 'c'], 'C:/a/b/c'),
      r'C:\..\a': ('C:/', ['a'], 'C:/a'),
      'C:/a/../..': ('C:/', [], 'C:/'),
      'z:/Mixed/CASE': ('Z:/', ['Mixed', 'CASE'], 'Z:/Mixed/CASE'),
      // UNC
      r'\\server\share\x': ('//server/share/', ['x'], '//server/share/x'),
      '//server/share': ('//server/share/', [], '//server/share/'),
      '//server/share/': ('//server/share/', [], '//server/share/'),
      '//server': ('//server/', [], '//server/'),
      '//server/': ('//server/', [], '//server/'),
      r'\\server\\share\\x': ('//server/share/', ['x'], '//server/share/x'),
      r'\/server/share/a/../b': ('//server/share/', ['b'], '//server/share/b'),
      '//Server/Share/A': ('//Server/Share/', ['A'], '//Server/Share/A'),
      '//server/share/..': ('//server/share/', [], '//server/share/'),
      r'\\.\pipe\name': ('//./pipe/', ['name'], '//./pipe/name'),
      // Mixed separators
      r'/a\b/c': ('/', ['a', 'b', 'c'], '/a/b/c'),
      r'a\b\\c': ('', ['a', 'b', 'c'], 'a/b/c'),
    };

    table.forEach((input, expected) {
      final (root, segments, string) = expected;
      test('parses ${input.isEmpty ? '(empty)' : input}', () {
        final path = TreePath.parse(input);
        expect(path.root, root);
        expect(path.segments, segments);
        expect(path.toString(), string);
        expect(path.isAbsolute, root.isNotEmpty);
        expect(path.isRoot, segments.isEmpty);
        expect(TreePath.parse(path.toString()), path, reason: 'round trip');
      });
    });

    test('throws FormatException for empty input, NUL, and escaping', () {
      for (final input in [
        '',
        'a\u0000b',
        '\u0000',
        '..',
        '../a',
        'a/../..',
        './..',
        r'..\x',
      ]) {
        expect(
          () => TreePath.parse(input),
          throwsFormatException,
          reason: input,
        );
        expect(TreePath.tryParse(input), isNull, reason: input);
      }
    });

    test('the escape error names the problem', () {
      expect(
        () => TreePath.parse('../a'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('escapes its root'),
          ),
        ),
      );
    });

    test('segments are unmodifiable', () {
      final path = TreePath.parse('/a/b');
      expect(() => path.segments.add('c'), throwsUnsupportedError);
    });
  });

  group('names and extensions', () {
    test('name of segments and roots', () {
      expect(TreePath.parse('/a/b').name, 'b');
      expect(TreePath.parse('/').name, '/');
      expect(TreePath.parse(r'c:\').name, 'C:');
      expect(TreePath.parse(r'\\server\share').name, '//server/share');
      expect(TreePath.parse('//server').name, '//server');
      expect(TreePath.parse('.').name, '.');
      expect(TreePath.parse('a').name, 'a');
    });

    test('extension', () {
      final table = <String, String>{
        '/x/a.dart': '.dart',
        '/x/.env': '',
        '/x/a.': '',
        '/x/archive.tar.gz': '.gz',
        '/x/README': '',
        '/x/..env': '.env',
        '/x/.env.local': '.local',
        '/x/File.TXT': '.TXT',
        '/x/lib.old': '.old',
        '/': '',
        'C:': '',
        '//srv.corp/share.x': '',
        '.': '',
      };
      table.forEach((input, extension) {
        expect(TreePath.parse(input).extension, extension, reason: input);
      });
    });
  });

  group('parent and child', () {
    test('parent drops the last segment and is null for roots', () {
      expect(TreePath.parse('/a/b').parent, TreePath.parse('/a'));
      expect(TreePath.parse('/a').parent, TreePath.parse('/'));
      expect(TreePath.parse('/').parent, isNull);
      expect(TreePath.parse('a').parent, TreePath.parse('.'));
      expect(TreePath.parse('.').parent, isNull);
      expect(TreePath.parse('C:/a').parent, TreePath.parse('C:'));
      expect(TreePath.parse('//s/sh/x').parent, TreePath.parse('//s/sh'));
      expect(TreePath.parse('./C:/x').parent.toString(), './C:');
    });

    test('child appends one segment', () {
      expect(TreePath.parse('/a').child('b'), TreePath.parse('/a/b'));
      expect(TreePath.parse('/').child('a'), TreePath.parse('/a'));
      expect(TreePath.parse('.').child('a'), TreePath.parse('a'));
      expect(TreePath.parse('C:').child('x'), TreePath.parse('C:/x'));
      expect(TreePath.parse('//s/sh').child('x'), TreePath.parse('//s/sh/x'));
      for (final base in ['/a', '/', '.', 'C:', 'a/b']) {
        final parent = TreePath.parse(base);
        expect(parent.child('n').parent, parent, reason: base);
      }
    });

    test('a drive-like first relative segment stays relative', () {
      final path = TreePath.parse('.').child('C:');
      expect(path.root, '');
      expect(path.segments, ['C:']);
      expect(path.toString(), './C:');
      expect(TreePath.parse(path.toString()), path);
      expect(path, isNot(TreePath.parse('C:')));
      expect(path.child('x').toString(), './C:/x');
    });

    test('child of a server-only UNC root becomes the share root', () {
      final share = TreePath.parse('//server').child('share');
      expect(share.root, '//server/share/');
      expect(share.isRoot, isTrue);
      expect(share, TreePath.parse('//server/share'));
    });

    test('child rejects invalid names', () {
      final path = TreePath.parse('/a');
      for (final name in ['', '.', '..', 'x/y', r'x\y', 'x\u0000']) {
        expect(() => path.child(name), throwsArgumentError, reason: name);
      }
    });
  });

  group('containment', () {
    test('isWithin is strict, exact, and root aware', () {
      expect(TreePath.parse('/a/b').isWithin(TreePath.parse('/a')), isTrue);
      expect(TreePath.parse('/a').isWithin(TreePath.parse('/')), isTrue);
      expect(TreePath.parse('/a').isWithin(TreePath.parse('/a')), isFalse);
      expect(TreePath.parse('/ab').isWithin(TreePath.parse('/a')), isFalse);
      expect(TreePath.parse('/A/b').isWithin(TreePath.parse('/a')), isFalse);
      expect(TreePath.parse('/a').isWithin(TreePath.parse('/a/b')), isFalse);
      expect(TreePath.parse('C:/a').isWithin(TreePath.parse('/')), isFalse);
      expect(TreePath.parse('a/b').isWithin(TreePath.parse('.')), isTrue);
      expect(
        TreePath.parse('//s/sh/x').isWithin(TreePath.parse('//s/sh')),
        isTrue,
      );
      expect(
        TreePath.parse('//s/sh/x').isWithin(TreePath.parse('//s')),
        isFalse,
      );
    });

    test('relativeTo returns the remaining segments', () {
      final relative = TreePath.parse(
        '/a/b/c',
      ).relativeTo(TreePath.parse('/a'))!;
      expect(relative.isAbsolute, isFalse);
      expect(relative.segments, ['b', 'c']);
      expect(relative.toString(), 'b/c');
      expect(
        TreePath.parse('/a').relativeTo(TreePath.parse('/a')).toString(),
        '.',
      );
      expect(TreePath.parse('/b').relativeTo(TreePath.parse('/a')), isNull);
      expect(TreePath.parse('/a').relativeTo(TreePath.parse('/a/b')), isNull);
      expect(TreePath.parse('C:/x').relativeTo(TreePath.parse('/')), isNull);
      final driveLike = TreePath.parse(
        '/C:/x',
      ).relativeTo(TreePath.parse('/'))!;
      expect(driveLike.toString(), './C:/x');
      expect(TreePath.parse(driveLike.toString()), driveLike);
    });
  });

  group('equality and order', () {
    test('equality is exact on the canonical string', () {
      expect(TreePath.parse('/a/'), TreePath.parse('/a'));
      expect(TreePath.parse(r'C:\x'), TreePath.parse('c:/x'));
      expect(TreePath.parse('/A'), isNot(TreePath.parse('/a')));
      expect(TreePath.parse('/a/b').hashCode, TreePath.parse(r'\a\b').hashCode);
      expect(TreePath.parse('a/b'), isNot(TreePath.parse('/a/b')));
    });

    test('compareTo orders by code units', () {
      final paths = ['/b', '/a/z', '/A', '/a', 'C:/a', 'a'].map(TreePath.parse);
      expect((paths.toList()..sort()).map((path) => path.toString()), [
        '/A',
        '/a',
        '/a/z',
        '/b',
        'C:/a',
        'a',
      ]);
      expect(TreePath.parse('/a').compareTo(TreePath.parse('/a/')), 0);
    });
  });

  group('generated corpus', () {
    const pieces = [
      'a',
      'B',
      'c.txt',
      '.',
      '..',
      '',
      'C:',
      'c:',
      'd:x',
      '.env',
      ' ',
      'é',
      'x y',
      'Ab',
    ];
    const separators = ['/', r'\', '//', r'\\', r'/\'];
    const prefixes = [
      '',
      '/',
      '//',
      '///',
      r'\\',
      'C:',
      r'c:\',
      'z:/',
      './',
      '../',
    ];

    List<String> corpus(int seed, int count) {
      final random = Random(seed);
      return List<String>.generate(count, (_) {
        final buffer = StringBuffer(prefixes[random.nextInt(prefixes.length)]);
        final length = random.nextInt(7);
        for (var i = 0; i < length; i++) {
          if (i > 0) {
            buffer.write(separators[random.nextInt(separators.length)]);
          }
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        if (random.nextInt(4) == 0) {
          buffer.write(separators[random.nextInt(separators.length)]);
        }
        return buffer.toString();
      });
    }

    final policies = <String, PathPolicy>{
      'default': const PathPolicy(),
      'case insensitive': PathPolicy.caseInsensitive,
      'no backslash': const PathPolicy(backslashIsSeparator: false),
    };

    policies.forEach((name, policy) {
      test('parse is idempotent ($name)', () {
        var valid = 0;
        var invalid = 0;
        for (final input in corpus(name.length, 3000)) {
          final path = policy.tryParse(input);
          if (path == null) {
            invalid++;
            continue;
          }
          valid++;
          expect(path.toString(), canonicalOracle(path), reason: input);
          final again = policy.parse(path.toString());
          expect(again, path, reason: input);
          expect(again.root, path.root, reason: input);
          expect(again.segments, path.segments, reason: input);
          expect(policy.idOf(again), policy.idOf(path), reason: input);
          for (final segment in path.segments) {
            expect(segment, isNot(anyOf('', '.', '..')), reason: input);
            expect(segment, isNot(contains('/')), reason: input);
            if (policy.backslashIsSeparator) {
              expect(segment, isNot(contains(r'\')), reason: input);
            }
          }
        }
        expect(valid, greaterThan(1000));
        expect(invalid, greaterThan(10));
      });
    });
  });
}
