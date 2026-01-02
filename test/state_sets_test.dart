import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

void main() {
  group('ExpansionSet', () {
    test('tracks expanded ids', () {
      final state = ExpansionSet(initiallyExpanded: {'a'});
      expect(state.isExpanded('a'), isTrue);
      expect(state.isExpanded('b'), isFalse);

      expect(state.setExpanded('b', true), isTrue);
      expect(state.isExpanded('b'), isTrue);

      expect(state.toggle('b'), isTrue);
      expect(state.isExpanded('b'), isFalse);

      expect(state.expandAll(['a', 'c']), isTrue);
      expect(state.expandedIds, containsAll(['a', 'c']));

      expect(state.retainWhere((id) => id == 'c'), isTrue);
      expect(state.expandedIds, equals({'c'}));

      expect(state.collapseAll(), isTrue);
      expect(state.expandedIds, isEmpty);
    });
  });

  group('SelectionSet', () {
    test('supports single mode', () {
      final state = SelectionSet(mode: SelectionMode.single);
      expect(state.selectOnly('a'), isTrue);
      expect(state.selectedIds, equals({'a'}));

      // Toggling the same id keeps selection and returns false (no change).
      expect(state.toggle('a'), isFalse);
      expect(state.selectedIds, equals({'a'}));

      expect(state.toggle('b'), isTrue);
      expect(state.selectedIds, equals({'b'}));
    });

    test('supports multi mode range and retain operations', () {
      final state = SelectionSet(mode: SelectionMode.multi);
      expect(state.toggle('a'), isTrue);
      expect(state.toggle('b'), isTrue);
      expect(state.selectedIds, equals({'a', 'b'}));

      expect(state.selectRange(['a', 'b', 'c', 'd'], 'b', 'd'), isTrue);
      expect(state.selectedIds, equals({'b', 'c', 'd'}));

      expect(state.addAll(['x', 'y']), isTrue);
      expect(state.selectedIds, containsAll(['x', 'y']));

      expect(state.removeAll(['x', 'z']), isTrue);
      expect(state.selectedIds.contains('x'), isFalse);

      expect(state.retainWhere((id) => id == 'b'), isTrue);
      expect(state.selectedIds, equals({'b'}));

      expect(state.clear(), isTrue);
      expect(state.selectedIds, isEmpty);
    });
  });
}
