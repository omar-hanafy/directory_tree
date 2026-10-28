import 'package:directory_tree/src/io/extended_length_path.dart';
import 'package:test/test.dart';

void main() {
  group('windowsExtendedLengthPath', () {
    // (input, expected)
    const table = <(String, String?)>[
      (r'C:\a\b', r'\\?\C:\a\b'),
      ('C:/a/b', r'\\?\C:\a\b'),
      (r'c:\a\b', r'\\?\c:\a\b'),
      (r'C:\a/b\c', r'\\?\C:\a\b\c'),
      (r'C:\a\.\b\..\c', r'\\?\C:\a\c'),
      (r'C:\..\..\a', r'\\?\C:\a'),
      (r'C:\a\\b\', r'\\?\C:\a\b'),
      (r'C:\', r'\\?\C:\'),
      (r'C:\a\..', r'\\?\C:\'),
      (r'\\server\share\a\b', r'\\?\UNC\server\share\a\b'),
      ('//server/share/a', r'\\?\UNC\server\share\a'),
      (r'\\server\share\..\a', r'\\?\UNC\server\share\a'),
      (r'\\server\share', r'\\?\UNC\server\share\'),
      (r'\\server', null),
      (r'\\server\', null),
      (r'\\\share\a', null),
      (r'\\?\C:\a', null),
      (r'\\?\UNC\server\share\a', null),
      (r'\\.\pipe\name', null),
      (r'a\b', null),
      (r'\a\b', null),
      ('C:a', null),
      ('C:', null),
      ('', null),
      ('1:/a', null),
    ];

    for (final (input, expected) in table) {
      test('"$input"', () {
        expect(windowsExtendedLengthPath(input), expected);
      });
    }

    test('keeps segment spelling and non-ASCII names', () {
      expect(
        windowsExtendedLengthPath(r'C:\Ünïcode\name with spaces\x.y'),
        r'\\?\C:\Ünïcode\name with spaces\x.y',
      );
    });
  });

  test('windowsMaxPath is the Win32 MAX_PATH', () {
    expect(windowsMaxPath, 260);
  });
}
