import 'package:directory_tree/src/ops/path_utils.dart';
import 'package:test/test.dart';

void main() {
  test('basename handles nested paths', () {
    expect(basename('/tmp/sub/file.txt'), 'file.txt');
    expect(basename('plain-name'), 'plain-name');
  });

  test('extensionLower normalizes case', () {
    expect(extensionLower('README.MD'), '.md');
    expect(extensionLower('noext'), '');
  });

  test('hasAnyExtension performs case-insensitive lookup', () {
    expect(hasAnyExtension('photo.JPG', ['.png', '.jpg']), isTrue);
    expect(hasAnyExtension('archive.zip', ['.tar']), isFalse);
  });
}
