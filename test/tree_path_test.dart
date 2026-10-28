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
      // Relative paths whose first segment looks like a drive print with a
      // './' prefix; containment still follows the segments.
      expect(TreePath.parse('./C:/x').isWithin(TreePath.parse('./C:')), isTrue);
      expect(TreePath.parse('./C:').isWithin(TreePath.parse('.')), isTrue);
      expect(TreePath.parse('C:/x').isWithin(TreePath.parse('./C:')), isFalse);
      expect(TreePath.parse('C:x/y').isWithin(TreePath.parse('./C:')), isFalse);
      expect(
        TreePath.parse('./C:/x/y').relativeTo(TreePath.parse('./C:')),
        TreePath.parse('x/y'),
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

  group('paths of tree nodes', () {
    // A tree stores the paths of nodes below its top-level nodes as a link
    // to the parent node's path plus a name, while parsing stores a full
    // segment list. Every observable behavior must be the same.
    const inputs = [
      '/repo/lib/src/a.dart',
      '/repo/lib/b.dart',
      '/repo/.env',
      '/repo/archive.tar.gz',
      '/Repo/README',
      r'C:\work\x\y.txt',
      'c:/work/z',
      r'\\server\share\docs\a.md',
      '//server/share/b',
      'rel/a/b',
      './C:/x/y',
      'd:x/e',
      '/a/b/c/',
    ];
    final policies = <String, PathPolicy>{
      'default': const PathPolicy(),
      'case insensitive': PathPolicy.caseInsensitive,
      'no backslash': const PathPolicy(backslashIsSeparator: false),
    };

    void expectSamePath(TreePath path, TreePath parsed, String reason) {
      expect(path, parsed, reason: reason);
      expect(path.hashCode, parsed.hashCode, reason: reason);
      expect(path.compareTo(parsed), 0, reason: reason);
      expect(path.toString(), parsed.toString(), reason: reason);
      expect(path.root, parsed.root, reason: reason);
      expect(path.segments, parsed.segments, reason: reason);
      expect(path.isRoot, parsed.isRoot, reason: reason);
      expect(path.isAbsolute, parsed.isAbsolute, reason: reason);
      expect(path.name, parsed.name, reason: reason);
      expect(path.extension, parsed.extension, reason: reason);
      expect(path.parent, parsed.parent, reason: reason);
      expect(path.child('x'), parsed.child('x'), reason: reason);
      expect(() => path.segments.add('x'), throwsUnsupportedError);
    }

    policies.forEach((name, policy) {
      test('behave like their parsed equivalents ($name)', () {
        final tree = DirectoryTree.fromPaths(
          inputs,
          options: TreeOptions(
            paths: policy,
            roots: const TreeRoots.filesystem(),
          ),
        );
        expect(tree.length, greaterThan(20));
        for (final node in tree.nodes) {
          final path = node.path;
          final parsed = policy.parse(path.toString());
          expectSamePath(path, parsed, '$path');
          // Containment against every ancestor and against a sibling.
          for (final ancestor in tree.ancestorsOf(node.id)) {
            final other = ancestor.path;
            final otherParsed = policy.parse(other.toString());
            expect(path.isWithin(other), isTrue, reason: '$path in $other');
            expect(other.isWithin(path), isFalse, reason: '$other in $path');
            expect(
              path.relativeTo(other),
              parsed.relativeTo(otherParsed),
              reason: '$path from $other',
            );
            expect(
              path.relativeTo(other)!.segments,
              parsed.segments.sublist(otherParsed.segments.length),
            );
          }
          expect(path.relativeTo(path), TreePath.parse('.'));
          final parent = tree.parentOf(node.id);
          if (parent != null) {
            for (final sibling in tree.childrenOf(parent.id)) {
              if (sibling.id == node.id) continue;
              expect(path.isWithin(sibling.path), isFalse);
              expect(path.relativeTo(sibling.path), isNull);
            }
          }
        }
      });
    });

    test('parent is the identical path of the parent node', () {
      final tree = DirectoryTree.fromPaths(inputs);
      for (final node in tree.nodes) {
        final parent = tree.parentOf(node.id);
        if (parent == null) continue;
        expect(identical(node.path.parent, parent.path), isTrue);
      }
    });

    test('a deep chain answers without recursion', () {
      const depth = 3000;
      final leaf = '/${List<String>.filled(depth, 'd').join('/')}/leaf.txt';
      // Filesystem roots materialize every directory below '/', so the
      // leaf's path links through 3001 node paths.
      final tree = DirectoryTree.fromPaths([
        leaf,
      ], options: const TreeOptions(roots: TreeRoots.filesystem()));
      expect(tree.length, depth + 2);
      final path = tree.nodeAt(leaf)!.path;
      expect(path.segments.length, depth + 1);
      expect(path.segments.first, 'd');
      expect(path.name, 'leaf.txt');
      expect(path.isWithin(tree.rootNodes.single.path), isTrue);
      expect(path.isWithin(TreePath.parse('/d/d')), isTrue);
      expect(path.relativeTo(TreePath.parse('/d'))!.segments.length, depth);
      expect(path.child('x').segments.length, depth + 2);
      var steps = 0;
      for (TreePath? up = path; up != null; up = up.parent) {
        steps++;
      }
      expect(steps, depth + 2);
    });

    test('a parsed path of 20000 segments supports every operation', () {
      const depth = 20000;
      final text = '/${List<String>.filled(depth, 's').join('/')}';
      final path = TreePath.parse(text);
      expect(path.segments.length, depth);
      expect(path.parent!.segments.length, depth - 1);
      expect(path.child('x').segments.length, depth + 1);
      expect(path.isWithin(TreePath.parse('/s')), isTrue);
      expect(path.relativeTo(TreePath.parse('/s/s'))!.segments.length, 19998);
      expect(TreePath.parse(path.toString()), path);
    });
  });

  group('canonical strings are shared, not copied', () {
    test('an already canonical input is its own canonical string', () {
      for (final input in [
        '/a/b.txt',
        'C:/a/b',
        '//server/share/x',
        'rel/a',
        'C:foo',
      ]) {
        expect(identical(TreePath.parse(input).toString(), input), isTrue);
      }
      // Inputs that need changes get an equal new string.
      for (final (input, canonical) in [
        ('/a//b', '/a/b'),
        ('/a/b/', '/a/b'),
        ('c:/a', 'C:/a'),
        (r'C:\a', 'C:/a'),
        ('//server//share/x', '//server/share/x'),
        ('./a', 'a'),
        ('/./a', '/a'),
        ('a/../C:/x', './C:/x'),
      ]) {
        expect(TreePath.parse(input).toString(), canonical, reason: input);
      }
    });

    test('a canonical entry path is shared by its node id and path', () {
      const input = '/repo/lib/a.dart';
      final tree = DirectoryTree.fromPaths([input, '/repo/b.dart']);
      final node = tree.nodeAt(input)!;
      expect(identical(node.id.value, input), isTrue);
      expect(identical(node.path.toString(), input), isTrue);
      expect(identical(node.entry!.path, input), isTrue);
    });

    test('a node spelled unlike its entry keeps the entry id', () {
      // Case-insensitive: the directory takes the smallest spelling 'Repo',
      // so the node of '/repo/b.txt' is displayed as '/Repo/b.txt'.
      const options = TreeOptions(paths: PathPolicy.caseInsensitive);
      const lower = '/repo/b.txt';
      final tree = DirectoryTree.fromPaths([
        '/Repo/a.txt',
        lower,
      ], options: options);
      final node = tree.nodeAt(lower)!;
      expect(node.path.toString(), '/Repo/b.txt');
      expect(identical(node.id.value, lower), isTrue);
      expect(node.id, options.paths.idOf(node.path));
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
