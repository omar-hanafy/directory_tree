import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

VisibleNode _node(String id, {int depth = 0}) => VisibleNode(
  id: id,
  depth: depth,
  name: id,
  type: NodeType.folder,
  hasChildren: false,
  virtualPath: '/$id',
);

void main() {
  test('diffVisibleNodes returns noop when lists are identical', () {
    final before = [_node('a'), _node('b')];
    final after = [_node('a'), _node('b')];

    final diff = diffVisibleNodes(before, after);

    expect(diff.isNoop, isTrue);
    expect(diff.removeIndicesDesc, isEmpty);
    expect(diff.insertIndicesAsc, isEmpty);
  });

  test('diffVisibleNodes computes removals and inserts', () {
    final before = [_node('a'), _node('b'), _node('c'), _node('d')];
    final after = [_node('b'), _node('e'), _node('d'), _node('f')];

    final diff = diffVisibleNodes(before, after);

    expect(diff.removeIndicesDesc, equals([2, 0]));
    expect(diff.insertIndicesAsc, equals([1, 3]));
  });

  test('diffVisibleNodes handles reorder without duplicates', () {
    final before = [_node('a'), _node('b'), _node('c')];
    final after = [_node('c'), _node('a'), _node('b')];

    final diff = diffVisibleNodes(before, after);

    // LIS keeps 'a','b'; remove 'c' at index 2, insert at position 0.
    expect(diff.removeIndicesDesc, equals([2]));
    expect(diff.insertIndicesAsc, equals([0]));
  });

  test(
    'diffVisibleNodes captures mixed inserts and removals around anchor',
    () {
      final before = [
        _node('anchor'),
        _node('b'),
        _node('c'),
        _node('d'),
        _node('e'),
      ];
      final after = [
        _node('inserted'),
        _node('anchor'),
        _node('d'),
        _node('e'),
        _node('tail'),
      ];

      final diff = diffVisibleNodes(before, after);

      expect(diff.removeIndicesDesc, equals([2, 1])); // remove c then b
      expect(diff.insertIndicesAsc, equals([0, 4]));
    },
  );
}
