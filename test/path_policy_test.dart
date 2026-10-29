import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

String composeAcute(String path) => path.replaceAll('e\u0301', '\u00e9');

void main() {
  group('defaults', () {
    test('the default policy is case sensitive and splits on backslash', () {
      const policy = PathPolicy();
      expect(policy.caseSensitive, isTrue);
      expect(policy.backslashIsSeparator, isTrue);
      expect(policy.unicodeNormalizer, isNull);
      expect(PathPolicy.caseInsensitive.caseSensitive, isFalse);
      expect(PathPolicy.caseInsensitive.backslashIsSeparator, isTrue);
    });
  });

  group('idOf', () {
    test('case-sensitive ids keep case', () {
      const policy = PathPolicy();
      expect(policy.idOf(policy.parse('/Repo/LIB')), const NodeId('/Repo/LIB'));
      expect(
        policy.idOf(policy.parse('/Repo/LIB')),
        isNot(policy.idOf(policy.parse('/repo/lib'))),
      );
    });

    test('case-insensitive ids fold case of every part', () {
      const policy = PathPolicy.caseInsensitive;
      expect(policy.idOf(policy.parse('/Repo/LIB')), const NodeId('/repo/lib'));
      expect(
        policy.idOf(policy.parse('/Repo/LIB')),
        policy.idOf(policy.parse('/repo/lib')),
      );
      expect(
        policy.idOf(policy.parse(r'\\Server\Share\X')),
        const NodeId('//server/share/x'),
      );
    });

    test('drive letters are equal across case in both modes', () {
      for (final policy in [const PathPolicy(), PathPolicy.caseInsensitive]) {
        expect(
          policy.idOf(policy.parse('c:/a')),
          policy.idOf(policy.parse(r'C:\a')),
          reason: '$policy',
        );
      }
      expect(
        const PathPolicy().idOf(const PathPolicy().parse('c:/a')),
        const NodeId('C:/a'),
      );
    });

    test('the display spelling is preserved by parse', () {
      expect(
        PathPolicy.caseInsensitive.parse('/Repo/A.txt').toString(),
        '/Repo/A.txt',
      );
    });
  });

  group('Win32 file namespace prefixes', () {
    test('name the same node as the path without them', () {
      final tree = DirectoryTree.fromPaths([
        r'C:\work\a.txt',
        r'\\?\c:\work\b.txt',
        r'\\server\share\c.txt',
        r'\\?\UNC\server\share\d.txt',
      ]);
      expect(tree.rootNodes.map((node) => node.path.toString()), [
        '//server/share/',
        'C:/work',
      ]);
      expect(tree.fileCount, 4);
      expect(tree.nodeAt(r'\\?\C:\work\a.txt'), tree.nodeAt('C:/work/a.txt'));
      expect(
        tree.idOf(r'\\?\UNC\server\share\c.txt'),
        tree.idOf(r'\\server\share\c.txt'),
      );
    });

    test('are literal when backslash is not a separator', () {
      const policy = PathPolicy(backslashIsSeparator: false);
      final windows = policy.parse(r'\\?\C:\x');
      expect(windows.root, '');
      expect(windows.segments, [r'\\?\C:\x']);
      final slashes = policy.parse('//?/C:/x');
      expect(slashes.root, '//?/C:/');
      expect(slashes.segments, ['x']);
    });
  });

  group('backslashIsSeparator: false', () {
    const policy = PathPolicy(backslashIsSeparator: false);

    test('backslash is an ordinary character', () {
      expect(policy.parse(r'C:\a').segments, [r'C:\a']);
      expect(policy.parse(r'C:\a').root, '');
      expect(policy.parse(r'\\server\share').segments, [r'\\server\share']);
      expect(policy.parse(r'/a\b/c').segments, [r'a\b', 'c']);
      expect(policy.parse(r'C:\').toString(), r'C:\');
    });

    test('slash rules still apply', () {
      expect(policy.parse('C:/a').root, 'C:/');
      expect(policy.parse('C:').root, 'C:/');
      expect(policy.parse('//server/share/x').root, '//server/share/');
      expect(policy.parse('/a/../b').toString(), '/b');
    });
  });

  group('unicodeNormalizer', () {
    test('is applied to the raw string before parsing', () {
      final seen = <String>[];
      final policy = PathPolicy(
        unicodeNormalizer: (path) {
          seen.add(path);
          return composeAcute(path);
        },
      );
      expect(policy.parse('/cafe\u0301/x'), policy.parse('/caf\u00e9/x'));
      expect(seen.first, '/cafe\u0301/x');
      expect(
        policy.idOf(policy.parse('/cafe\u0301')),
        policy.idOf(policy.parse('/caf\u00e9')),
      );
    });

    test('can change separators because it runs first', () {
      final policy = PathPolicy(
        unicodeNormalizer: (path) => path.replaceAll('|', '/'),
      );
      expect(policy.parse('a|b|c').segments, ['a', 'b', 'c']);
    });

    test('an empty or NUL result is a FormatException', () {
      final empty = PathPolicy(unicodeNormalizer: (path) => '');
      expect(
        () => empty.parse('/a'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('normalization'),
          ),
        ),
      );
      final nul = PathPolicy(unicodeNormalizer: (path) => '$path\u0000');
      expect(() => nul.parse('/a'), throwsFormatException);
      expect(nul.tryParse('/a'), isNull);
    });

    test('tryParse lets other normalizer errors propagate', () {
      final failing = PathPolicy(
        unicodeNormalizer: (path) => throw StateError('boom'),
      );
      expect(() => failing.tryParse('/a'), throwsStateError);
    });
  });

  group('errors', () {
    test('FormatExceptions carry the raw source', () {
      expect(
        () => const PathPolicy().parse('a\u0000b'),
        throwsA(
          isA<FormatException>()
              .having((error) => error.message, 'message', contains('NUL'))
              .having((error) => error.source, 'source', 'a\u0000b')
              .having((error) => error.offset, 'offset', 1),
        ),
      );
      expect(
        () => const PathPolicy().parse(''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('tryParse returns null for invalid paths', () {
      expect(const PathPolicy().tryParse(''), isNull);
      expect(const PathPolicy().tryParse('../x'), isNull);
      expect(const PathPolicy().tryParse('x'), isNotNull);
    });
  });

  group('value semantics', () {
    test('== and hashCode compare settings', () {
      expect(const PathPolicy(), const PathPolicy());
      expect(
        const PathPolicy(caseSensitive: false),
        PathPolicy.caseInsensitive,
      );
      expect(
        const PathPolicy(caseSensitive: false).hashCode,
        PathPolicy.caseInsensitive.hashCode,
      );
      expect(const PathPolicy(), isNot(PathPolicy.caseInsensitive));
      expect(
        const PathPolicy(),
        isNot(const PathPolicy(backslashIsSeparator: false)),
      );
    });

    test('normalizers compare with ==', () {
      const a = PathPolicy(unicodeNormalizer: composeAcute);
      const b = PathPolicy(unicodeNormalizer: composeAcute);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        PathPolicy(unicodeNormalizer: (path) => path),
        isNot(PathPolicy(unicodeNormalizer: (path) => path)),
      );
    });

    test('toString lists the settings', () {
      expect(
        const PathPolicy().toString(),
        'PathPolicy(caseSensitive: true, backslashIsSeparator: true, '
        'unicodeNormalizer: none)',
      );
      expect(
        const PathPolicy(unicodeNormalizer: composeAcute).toString(),
        contains('unicodeNormalizer: custom'),
      );
    });
  });
}
