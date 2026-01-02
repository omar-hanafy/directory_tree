import 'package:directory_tree/src/ops/path_utils.dart';
import 'package:directory_tree/src/ops/search_filter.dart';
import 'package:test/test.dart';

void main() {
  group('compileFilter', () {
    test('matches when query is null or empty', () {
      final predNull = compileFilter(null);
      final predEmpty = compileFilter('   ');

      expect(predNull('anything', extensionLower('anything')), isTrue);
      expect(predEmpty('something', extensionLower('file.txt')), isTrue);
    });

    test('supports substring, extension, and negation tokens', () {
      final predicate = compileFilter('doc ext:md !draft');

      expect(predicate('project_doc.md', '.md'), isTrue);
      expect(predicate('draft.md', '.md'), isFalse);
      expect(predicate('project_doc.txt', '.txt'), isFalse);
    });
  });
}
