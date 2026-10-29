import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/src/path/case_folding.dart';
import 'package:directory_tree/src/path/tree_path.dart' show isAsciiLetter;
import 'package:test/test.dart';

// Every expectation here is a literal, so the file pins one result for the
// VM, JavaScript, and WebAssembly; CI runs it on all three. Platform
// `toLowerCase` tables differ between them (and between JavaScript engine
// versions), which is what the package's own table avoids.

const String kelvin = 'K'; // KELVIN SIGN
const String capitalSharpS = 'ẞ'; // LATIN CAPITAL LETTER SHARP S
const String dottedI = 'İ'; // LATIN CAPITAL LETTER I WITH DOT ABOVE
const String micro = 'µ'; // MICRO SIGN
const String longS = 'ſ'; // LATIN SMALL LETTER LONG S
const String cherokeeA = 'Ꭰ'; // CHEROKEE LETTER A
const String cherokeeSmallA = 'ꭰ'; // CHEROKEE SMALL LETTER A
const String cherokeeYe = 'Ᏽ'; // CHEROKEE LETTER MV
const String cherokeeSmallYe = 'ᏽ'; // CHEROKEE SMALL LETTER MV
const String ligature = '\u{1DF95}'; // LONG S WITH DESCENDER S, 2 units

int utf16Length(int codePoint) => codePoint > 0xFFFF ? 2 : 1;

String hex(int codePoint) => 'U+${codePoint.toRadixString(16).toUpperCase()}';

void main() {
  group('the table', () {
    test('is pinned to Unicode 18.0.0', () {
      expect(caseFoldingUnicodeVersion, '18.0.0');
    });

    test('is idempotent and keeps UTF-16 lengths except U+1DF95', () {
      var changed = 0;
      final lengthChanges = <int>[];
      for (var codePoint = 0; codePoint <= 0x10FFFF; codePoint++) {
        final folded = foldCodePoint(codePoint);
        if (folded == codePoint) continue;
        changed++;
        expect(
          foldCodePoint(folded),
          folded,
          reason: '${hex(codePoint)} folds to ${hex(folded)}, not a fixpoint',
        );
        expect(folded, isNot(inInclusiveRange(0x30, 0x39)));
        expect(folded, isNot(0x2F));
        if (utf16Length(folded) != utf16Length(codePoint)) {
          lengthChanges.add(codePoint);
        }
      }
      // CaseFolding.txt 18.0.0 has 1533 mappings with status C or S.
      expect(changed, 1533);
      // TreeQuery translates indexes for this one; anything new must be
      // reviewed (tool/generate_case_folding.dart refuses it too).
      expect(lengthChanges, [0x1DF95]);
      expect(foldCodePoint(0x1DF95), 0xDF);
    });

    test(
      'folds only U+017F and U+212A from outside ASCII to ASCII letters',
      () {
        // TreePath prefixes a relative path with './' when its first segment
        // folds to a drive spec, deciding from the first code unit only. That
        // is exact only while every code point that folds to an ASCII letter
        // is a single UTF-16 code unit; a new one must be reviewed there.
        final toAsciiLetter = <int>[
          for (var codePoint = 0x80; codePoint <= 0x10FFFF; codePoint++)
            if (isAsciiLetter(foldCodePoint(codePoint))) codePoint,
        ];
        expect(toAsciiLetter, [0x017F, 0x212A]);
        final drives = [
          for (final codePoint in toAsciiLetter)
            TreePath.parse('${String.fromCharCode(codePoint)}:/x'),
        ];
        expect(drives.map((path) => path.toString()), [
          './\u017F:/x',
          './\u212A:/x',
        ]);
      },
    );

    final spots = <int, int>{
      0x41: 0x61, // A
      0x5A: 0x7A, // Z
      0x61: 0x61, // a stays
      0x40: 0x40, // @ stays
      0xB5: 0x3BC, // MICRO SIGN to Greek mu
      0xC0: 0xE0, // A with grave
      0xDF: 0xDF, // sharp s has only a full folding (ss)
      0x130: 0x130, // I with dot above has only full and Turkic foldings
      0x131: 0x131, // dotless i has no folding
      0x17F: 0x73, // long s to s
      0x1C5: 0x1C6, // titlecase Dz with caron
      0x345: 0x3B9, // combining ypogegrammeni to iota
      0x3A3: 0x3C3, // capital sigma
      0x3C2: 0x3C3, // final sigma
      0x3C3: 0x3C3, // sigma stays
      0x3F4: 0x3B8, // capital theta symbol
      0x1E9E: 0xDF, // capital sharp s
      0x2126: 0x3C9, // OHM SIGN to omega
      0x212A: 0x6B, // KELVIN SIGN to k
      0x212B: 0xE5, // ANGSTROM SIGN to a with ring
      0x13A0: 0x13A0, // Cherokee uppercase stays
      0x13F8: 0x13F0, // Cherokee small ye to uppercase
      0xAB70: 0x13A0, // Cherokee small a to uppercase
      0x10A0: 0x2D00, // Georgian capital an (Asomtavruli)
      0x1C90: 0x10D0, // Georgian Mtavruli an
      0xA7C0: 0xA7C1, // Latin Extended-D
      0xFF21: 0xFF41, // fullwidth A
      0x10400: 0x10428, // Deseret
      0x104B0: 0x104D8, // Osage
      0x1E900: 0x1E922, // Adlam
      0x1DF95: 0xDF, // long s with descender s ligature
      0xD800: 0xD800, // a surrogate code point
      0x10FFFF: 0x10FFFF,
    };
    for (final MapEntry(key: from, value: to) in spots.entries) {
      test('folds ${hex(from)} to ${hex(to)}', () {
        expect(foldCodePoint(from), to);
      });
    }
  });

  group('foldCase', () {
    test('returns the same string when nothing changes', () {
      for (final text in ['', 'abc/def', 'οδοσ', 'ß', '😀x', '\uD800']) {
        expect(identical(foldCase(text), text), isTrue, reason: text);
      }
    });

    test('folds per code point, with no context', () {
      expect(foldCase('/R/ΟΔΟΣ'), '/r/οδοσ');
      expect(foldCase('/r/οδος'), '/r/οδοσ');
      expect(foldCase('ΣΑΣ ΣΑς'), 'σασ σασ');
      expect(foldCase('${dottedI}stanbul'), '${dottedI}stanbul');
      expect(foldCase('ISTANBUL'), 'istanbul');
      expect(foldCase('${kelvin}B'), 'kb');
      expect(foldCase('${capitalSharpS}A'), 'ßa');
      expect(
        foldCase('$cherokeeSmallA$cherokeeSmallYe'),
        '$cherokeeA$cherokeeYe',
      );
      expect(foldCase('$micro$longS'), 'μs');
      // Astral letters fold as decoded pairs.
      expect(foldCase('\u{10400}\u{1E900}'), '\u{10428}\u{1E922}');
      // An unpaired surrogate is kept as it is.
      expect(foldCase('A\uD800B\uDC00C'), 'a\uD800b\uDC00c');
    });

    test('shortens text only for U+1DF95', () {
      final folded = foldCase('A${ligature}B');
      expect(folded, 'aßb');
      expect(folded.length, 3);
    });

    test('folding the parts equals folding the joined string', () {
      const parts = ['ΟΔΟΣ', 'odoς', '${dottedI}X', 'ꭰᏵ', '$kelvin$ligature'];
      expect(foldCase(parts.join('/')), parts.map(foldCase).join('/'));
    });
  });

  group('case-insensitive trees', () {
    const options = TreeOptions(paths: PathPolicy.caseInsensitive);

    test('every sigma spelling has one id and merges into one node', () {
      const policy = PathPolicy.caseInsensitive;
      final ids = {
        for (final path in ['/r/ΟΔΟΣ', '/r/οδος', '/r/οδοσ', '/r/ΟΔΟς'])
          policy.idOf(policy.parse(path)),
      };
      expect(ids, {const NodeId('/r/οδοσ')});

      final tree = DirectoryTree.fromPaths([
        '/r/ΟΔΟΣ/a.txt',
        '/r/οδος/b.txt',
        '/r/οδοσ/c.txt',
      ], options: options);
      // One directory, shown with the code-unit-smallest spelling.
      expect(tree.directories.map((node) => node.path.toString()), ['/r/ΟΔΟΣ']);
      expect(tree.idOf('/r/οδος'), const NodeId('/r/οδοσ'));
      expect(tree.fileCount, 3);
    });

    test('dotted capital I does not merge with i', () {
      final tree = DirectoryTree.fromPaths([
        '/r/${dottedI}stanbul.txt',
        '/r/istanbul.txt',
        '/r/ISTANBUL.txt',
      ], options: options);
      expect(tree.files.map((node) => node.id.value), [
        '/r/istanbul.txt',
        '/r/${dottedI}stanbul.txt',
      ]);
    });

    test('Cherokee lowercase merges with its uppercase', () {
      final tree = DirectoryTree.fromPaths([
        '/r/$cherokeeA$cherokeeYe.txt',
        '/r/$cherokeeSmallA$cherokeeSmallYe.txt',
        '/r/$cherokeeSmallA$cherokeeYe.txt',
      ], options: options);
      expect(tree.fileCount, 1);
      expect(tree.files.single.id.value, '/r/$cherokeeA$cherokeeYe.txt');
    });

    test('the Kelvin sign, capital sharp s, and the ligature merge', () {
      final tree = DirectoryTree.fromPaths([
        '/r/${kelvin}m',
        '/r/km',
        '/r/${capitalSharpS}x',
        '/r/ßx',
        '/r/${ligature}x',
        '/r/ssx',
      ], options: options);
      expect(tree.files.map((node) => node.id.value), [
        '/r/km',
        '/r/ssx',
        '/r/ßx',
      ]);
    });

    test('rebuilding keeps ids and node order', () {
      final tree = DirectoryTree.fromPaths([
        '/R/ΟΔΟΣ/x',
        '/r/οδος/y',
        '/r/$cherokeeSmallA/z',
        '/r/$cherokeeA/w',
        '/r/$dottedI/v',
      ], options: options);
      expect(tree.rebuild((_) {}), tree);
      expect(DirectoryTree.build(tree.entries, options: options), tree);
    });
  });

  group('TreeOrder.compareNames', () {
    test('sorts Greek, Turkish, Cherokee, and Kelvin names the same way '
        'everywhere', () {
      final names = [
        'Οδός',
        '${cherokeeA}2',
        'key',
        '${dottedI}zmir.txt',
        'ΟΔΟΣ',
        'Jena.txt',
        '${micro}2',
        'ſun',
        '${capitalSharpS}a',
        'sea',
        '${cherokeeSmallA}1',
        'οδος',
        '${kelvin}elvin',
        'izmir.txt',
        'Sun',
        'ßb',
        'μ1',
      ]..sort(TreeOrder.compareNames);
      expect(names, [
        'izmir.txt',
        'Jena.txt',
        '${kelvin}elvin',
        'key',
        'sea',
        'Sun',
        'ſun',
        '${capitalSharpS}a',
        'ßb',
        '${dottedI}zmir.txt',
        'μ1',
        '${micro}2',
        'ΟΔΟΣ',
        'οδος',
        'Οδός',
        '${cherokeeSmallA}1',
        '${cherokeeA}2',
      ]);
    });

    test('the default order puts Jena before Izmir with a dot', () {
      final tree = DirectoryTree.fromPaths([
        '/r/${dottedI}zmir.txt',
        '/r/Jena.txt',
      ]);
      expect(tree.files.map((node) => node.name), [
        'Jena.txt',
        '${dottedI}zmir.txt',
      ]);
    });

    test('folded names compare equal before the code-unit tie-break', () {
      expect(TreeOrder.compareNames('ς', 'σ'), lessThan(0));
      expect(TreeOrder.compareNames('ςb', 'σa'), greaterThan(0));
      expect(TreeOrder.compareNames('${kelvin}b', 'ka'), greaterThan(0));
      expect(TreeOrder.compareNames('${ligature}b', 'ßa'), greaterThan(0));
      expect(TreeOrder.compareNames('${ligature}a', 'ßb'), lessThan(0));
    });

    test('non-ASCII code points keep UTF-16 code unit order', () {
      // U+FF21 (fullwidth A) folds to U+FF41, which follows every astral
      // code point in UTF-16 order, as in String.compareTo.
      const astral = '\u{1F600}';
      expect(TreeOrder.compareNames('Ａ', astral), greaterThan(0));
      expect(TreeOrder.compareNames('퟿', astral), lessThan(0));
      expect(
        TreeOrder.compareNames('\u{10400}', '\u{10429}'),
        lessThan(0),
        reason: 'Deseret capital long I folds to U+10428',
      );
    });
  });

  group('TreeQuery', () {
    final tree = DirectoryTree.fromPaths([
      '/u/ΟΔΟΣ.md',
      '/u/odoς.md',
      '/u/${dottedI}stanbul.txt',
      '/u/istanbul.txt',
      '/u/$cherokeeA$cherokeeYe.txt',
      '/u/${kelvin}elvin.txt',
      '/u/$capitalSharpS.txt',
      '/u/x${ligature}y/leaf',
      '/u/a${ligature}b/c${ligature}d/end',
    ]);
    Set<String> names(String query, {bool caseSensitive = false}) {
      final parsed = TreeQuery.parse(query, caseSensitive: caseSensitive);
      return {
        for (final node in tree.nodes)
          if (parsed.matches(node)) node.name,
      };
    }

    final cases = <String, Set<String>>{
      'οδοσ': {'ΟΔΟΣ.md'},
      'οδος': {'ΟΔΟΣ.md'},
      'ΟΔΟς': {'ΟΔΟΣ.md'},
      'odoσ': {'odoς.md'},
      '${dottedI}stan': {'${dottedI}stanbul.txt'},
      'istan': {'istanbul.txt'},
      'ISTAN': {'istanbul.txt'},
      'stanbul': {'${dottedI}stanbul.txt', 'istanbul.txt'},
      '$cherokeeSmallA$cherokeeSmallYe': {'$cherokeeA$cherokeeYe.txt'},
      'kelvin': {'${kelvin}elvin.txt'},
      '${kelvin}ELVIN': {'${kelvin}elvin.txt'},
      'ß': {
        '$capitalSharpS.txt',
        'x${ligature}y',
        'a${ligature}b',
        'c${ligature}d',
      },
      'ss': {},
      // A trailing separator reaches the names of a folder's children, also
      // after a character that folding shortens.
      'ßy/': {'leaf'},
      '${ligature}y/': {'leaf'},
      'ßy/l': {'leaf'},
      // A glob over the last path components.
      'c*/end': {'end'},
      'aß?/c*': {'c${ligature}d'},
    };
    for (final MapEntry(key: query, value: expected) in cases.entries) {
      test('$query matches $expected', () {
        expect(names(query), expected);
      });
    }

    test('case-sensitive queries do not fold', () {
      expect(names('ß', caseSensitive: true), isEmpty);
      expect(names('οδος', caseSensitive: true), isEmpty);
      expect(names(kelvin, caseSensitive: true), {'${kelvin}elvin.txt'});
    });

    final ranges = <(String, String, List<({int start, int end})>)>[
      ('οδοσ', 'ΟΔΟΣ.md', [(start: 0, end: 4)]),
      ('σ', 'ΣΑς', [(start: 0, end: 1), (start: 2, end: 3)]),
      ('stan', '${dottedI}stanbul', [(start: 1, end: 5)]),
      ('istan', '${dottedI}stanbul', []),
      ('ꭰ', '$cherokeeA$cherokeeSmallA', [(start: 0, end: 2)]),
      ('k', '${kelvin}elvin', [(start: 0, end: 1)]),
      ('ß', 'a${capitalSharpS}b', [(start: 1, end: 2)]),
      // U+1DF95 is two code units of the text but one of its folded form;
      // ranges are in code units of the text as given.
      ('ß', 'a${ligature}b', [(start: 1, end: 3)]),
      ('ßb', 'a${ligature}b', [(start: 1, end: 4)]),
      (
        'b',
        'a${ligature}b${ligature}b',
        [(start: 3, end: 4), (start: 6, end: 7)],
      ),
      ('a ß', 'a$ligature', [(start: 0, end: 3)]),
      ('xß/', 'x$ligature/leaf', [(start: 0, end: 4)]),
    ];
    for (final (query, text, expected) in ranges) {
      test('matchRanges of $query in $text', () {
        final actual = TreeQuery.parse(query).matchRanges(text);
        expect(actual, expected);
        for (final range in actual) {
          // Every range covers whole code points of the text.
          expect(range.start, inInclusiveRange(0, text.length));
          expect(range.end, inInclusiveRange(range.start + 1, text.length));
        }
      });
    }
  });
}
