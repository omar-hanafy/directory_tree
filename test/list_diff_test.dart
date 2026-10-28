import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/src/diff/list_diff.dart';
import 'package:test/test.dart';

String _self(String item) => item;

ListDiff _diff(List<String> before, List<String> after) =>
    ListDiff.compute(before, after, keyOf: _self);

/// Applies [diff] the way an animated list does and returns the keys.
List<K> _apply<E, K>(
  List<E> before,
  List<E> after,
  ListDiff diff,
  K Function(E item) keyOf,
) {
  final working = List<E>.of(before);
  for (final index in diff.removedIndices) {
    working.removeAt(index);
  }
  for (final index in diff.insertedIndices) {
    working.insert(index, after[index]);
  }
  return [for (final item in working) keyOf(item)];
}

/// Quadratic dynamic-programming oracle: the length of the longest common
/// subsequence of two key lists with unique keys (= LIS of the mapped
/// indices).
int _oracleKeptCount(List<int> before, List<int> after) {
  final position = {for (var i = 0; i < after.length; i++) after[i]: i};
  final sequence = [
    for (final key in before)
      if (position.containsKey(key)) position[key]!,
  ];
  final best = List<int>.filled(sequence.length, 1);
  var result = 0;
  for (var i = 0; i < sequence.length; i++) {
    for (var j = 0; j < i; j++) {
      if (sequence[j] < sequence[i] && best[j] + 1 > best[i]) {
        best[i] = best[j] + 1;
      }
    }
    result = max(result, best[i]);
  }
  return result;
}

/// A random list of unique keys drawn from 0..<pool, in random order.
List<int> _randomKeys(Random random, int length, int pool) {
  final all = List<int>.generate(pool, (i) => i)..shuffle(random);
  return all.sublist(0, length);
}

/// [before] edited by random removals, insertions of new keys, and moves.
List<int> _edit(Random random, List<int> before, int nextKey, int edits) {
  final result = List<int>.of(before);
  var fresh = nextKey;
  for (var e = 0; e < edits; e++) {
    final op = random.nextInt(3);
    if (op == 0 && result.isNotEmpty) {
      result.removeAt(random.nextInt(result.length));
    } else if (op == 1) {
      result.insert(random.nextInt(result.length + 1), fresh++);
    } else if (result.isNotEmpty) {
      final item = result.removeAt(random.nextInt(result.length));
      result.insert(random.nextInt(result.length + 1), item);
    }
  }
  return result;
}

void _expectWellFormed(ListDiff diff, int beforeLength, int afterLength) {
  final removed = diff.removedIndices;
  for (var i = 1; i < removed.length; i++) {
    expect(removed[i - 1], greaterThan(removed[i]), reason: 'descending');
  }
  for (final list in [diff.insertedIndices, diff.changedIndices]) {
    for (var i = 1; i < list.length; i++) {
      expect(list[i - 1], lessThan(list[i]), reason: 'ascending');
    }
  }
  expect(removed.every((i) => i >= 0 && i < beforeLength), isTrue);
  expect(diff.insertedIndices.every((i) => i >= 0 && i < afterLength), isTrue);
  expect(
    diff.changedIndices.toSet().intersection(diff.insertedIndices.toSet()),
    isEmpty,
  );
  expect(
    beforeLength - removed.length,
    afterLength - diff.insertedIndices.length,
    reason: 'kept counts agree',
  );
}

void main() {
  group('ListDiff.compute hand cases', () {
    test('two empty lists give an empty diff', () {
      final diff = _diff(const [], const []);
      expect(diff.isEmpty, isTrue);
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, isEmpty);
      expect(diff.changedIndices, isEmpty);
    });

    test('from an empty list everything is inserted', () {
      final diff = _diff(const [], const ['a', 'b', 'c']);
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, [0, 1, 2]);
      expect(diff.isEmpty, isFalse);
    });

    test('to an empty list everything is removed, last first', () {
      final diff = _diff(const ['a', 'b', 'c'], const []);
      expect(diff.removedIndices, [2, 1, 0]);
      expect(diff.insertedIndices, isEmpty);
    });

    test('all new keys: remove everything, insert everything', () {
      final diff = _diff(const ['a', 'b'], const ['x', 'y', 'z']);
      expect(diff.removedIndices, [1, 0]);
      expect(diff.insertedIndices, [0, 1, 2]);
    });

    test('a reversal keeps exactly one item', () {
      const before = ['a', 'b', 'c', 'd'];
      const after = ['d', 'c', 'b', 'a'];
      final diff = _diff(before, after);
      expect(diff.removedIndices, [2, 1, 0]);
      expect(diff.insertedIndices, [1, 2, 3]);
      expect(_apply(before, after, diff, _self), after);
    });

    test('a single move is one removal and one insertion', () {
      const before = ['a', 'b', 'c', 'd', 'e'];
      const after = ['a', 'c', 'd', 'b', 'e'];
      final diff = _diff(before, after);
      expect(diff.removedIndices, [1]);
      expect(diff.insertedIndices, [3]);
      expect(diff.changedIndices, isEmpty);
      expect(_apply(before, after, diff, _self), after);
    });

    test('interleaved insertions and a removal', () {
      const before = ['a', 'b', 'c'];
      const after = ['x', 'a', 'y', 'c', 'z'];
      final diff = _diff(before, after);
      expect(diff.removedIndices, [1]);
      expect(diff.insertedIndices, [0, 2, 4]);
      expect(_apply(before, after, diff, _self), after);
    });

    test('the same list instance gives an empty diff', () {
      final list = ['a', 'b', 'c'];
      expect(_diff(list, list).isEmpty, isTrue);
    });

    test('equal key sequences only report changes', () {
      final before = [(id: 1, v: 'a'), (id: 2, v: 'b'), (id: 3, v: 'c')];
      final after = [(id: 1, v: 'a'), (id: 2, v: 'B'), (id: 3, v: 'c')];
      final diff = ListDiff.compute(before, after, keyOf: (item) => item.id);
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, isEmpty);
      expect(diff.changedIndices, [1]);
      expect(diff.isEmpty, isFalse);
    });
  });

  group('ListDiff.compute changed detection', () {
    test('default equality is ==', () {
      final before = [(id: 1, v: 'a'), (id: 2, v: 'b'), (id: 3, v: 'c')];
      final after = [(id: 3, v: 'C'), (id: 1, v: 'a'), (id: 2, v: 'B')];
      final diff = ListDiff.compute(before, after, keyOf: (item) => item.id);
      // 1 and 2 are kept (at after indices 1 and 2); 3 moved.
      expect(diff.removedIndices, [2]);
      expect(diff.insertedIndices, [0]);
      expect(diff.changedIndices, [2]);
    });

    test('a custom equals decides what changed', () {
      final before = [(id: 1, v: 'a'), (id: 2, v: 'b'), (id: 3, v: 'c')];
      final after = [(id: 1, v: 'A'), (id: 2, v: 'b'), (id: 3, v: 'X')];
      final calls = <(int, int)>[];
      final diff = ListDiff.compute(
        before,
        after,
        keyOf: (item) => item.id,
        equals: (a, b) {
          calls.add((a.id, b.id));
          return a.v.toLowerCase() == b.v.toLowerCase();
        },
      );
      expect(diff.changedIndices, [2]);
      expect(calls, [(1, 1), (2, 2), (3, 3)]);
    });

    test('equals is called only for kept items', () {
      final before = ['a', 'b', 'c'];
      final after = ['d', 'a', 'c'];
      final calls = <String>[];
      ListDiff.compute(
        before,
        after,
        keyOf: _self,
        equals: (a, b) {
          calls.add('$a=$b');
          return true;
        },
      );
      expect(calls, ['a=a', 'c=c']);
    });

    test('a kept item can be changed while others move', () {
      final before = [(id: 'a', n: 1), (id: 'b', n: 1), (id: 'c', n: 1)];
      final after = [(id: 'b', n: 2), (id: 'c', n: 1), (id: 'a', n: 1)];
      final diff = ListDiff.compute(before, after, keyOf: (item) => item.id);
      expect(diff.removedIndices, [0]);
      expect(diff.insertedIndices, [2]);
      expect(diff.changedIndices, [0]);
    });
  });

  group('ListDiff.compute duplicate keys', () {
    test('a duplicate in before throws naming the key and the list', () {
      expect(
        () => _diff(const ['a', 'dup', 'b', 'dup'], const ['a']),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'before')
              .having((e) => '${e.message}', 'message', contains('dup'))
              .having((e) => '${e.message}', 'message', contains('1 and 3')),
        ),
      );
    });

    test('a duplicate in after throws naming the key and the list', () {
      expect(
        () => _diff(const ['a', 'b'], const ['b', 'twice', 'twice']),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'after')
              .having((e) => '${e.message}', 'message', contains('twice')),
        ),
      );
    });

    test('duplicates throw on the equal-keys fast path too', () {
      final list = ['x', 'x'];
      expect(() => _diff(list, list), throwsArgumentError);
      expect(() => _diff(['x', 'x'], ['x', 'x']), throwsArgumentError);
    });

    test('equal items with distinct keys are fine', () {
      final before = [(id: 1, v: 'same'), (id: 2, v: 'same')];
      final after = [(id: 2, v: 'same'), (id: 1, v: 'same')];
      final diff = ListDiff.compute(before, after, keyOf: (item) => item.id);
      expect(diff.removedIndices.length, 1);
      expect(diff.insertedIndices.length, 1);
    });
  });

  group('ListDiff.compute properties', () {
    test('apply contract and minimality on small random lists', () {
      final random = Random(20261028);
      for (var round = 0; round < 2000; round++) {
        final pool = 1 + random.nextInt(25);
        final before = _randomKeys(random, random.nextInt(pool + 1), pool);
        final after = random.nextBool()
            ? _randomKeys(random, random.nextInt(pool + 1), pool)
            : _edit(random, before, pool, random.nextInt(6));
        final diff = ListDiff.compute(before, after, keyOf: (int key) => key);
        final reason = 'before: $before, after: $after, diff: $diff';
        _expectWellFormed(diff, before.length, after.length);
        expect(
          _apply(before, after, diff, (int key) => key),
          after,
          reason: reason,
        );
        expect(
          before.length - diff.removedIndices.length,
          _oracleKeptCount(before, after),
          reason: reason,
        );
        expect(diff.changedIndices, isEmpty, reason: reason);
      }
    });

    test('changedIndices are exactly the kept items that differ', () {
      final random = Random(7);
      for (var round = 0; round < 500; round++) {
        final keys = _randomKeys(random, random.nextInt(30), 40);
        final afterKeys = _edit(random, keys, 40, random.nextInt(8));
        final version = {for (final key in afterKeys) key: random.nextInt(2)};
        final before = [for (final key in keys) (key: key, version: 0)];
        final after = [
          for (final key in afterKeys) (key: key, version: version[key]!),
        ];
        final diff = ListDiff.compute(before, after, keyOf: (item) => item.key);
        final inserted = diff.insertedIndices.toSet();
        final beforeKeys = keys.toSet();
        final expected = [
          for (var i = 0; i < after.length; i++)
            if (!inserted.contains(i) &&
                beforeKeys.contains(after[i].key) &&
                after[i].version != 0)
              i,
        ];
        expect(diff.changedIndices, expected);
      }
    });

    test('apply contract on large random lists', () {
      final random = Random(50000);
      for (final (size, edits) in [(50000, 200), (50000, 50000), (20000, 5)]) {
        final before = _randomKeys(random, size, size);
        final after = _edit(random, before, size, edits);
        final diff = ListDiff.compute(before, after, keyOf: (int key) => key);
        _expectWellFormed(diff, before.length, after.length);
        expect(_apply(before, after, diff, (int key) => key), after);
      }
    });

    test('a 50k reversal and a 50k identical-keys copy', () {
      final before = List<int>.generate(50000, (i) => i);
      final reversed = before.reversed.toList();
      final diff = ListDiff.compute(before, reversed, keyOf: (int key) => key);
      expect(diff.removedIndices.length, 49999);
      expect(_apply(before, reversed, diff, (int key) => key), reversed);

      final copy = List<int>.of(before);
      expect(
        ListDiff.compute(before, copy, keyOf: (int key) => key).isEmpty,
        isTrue,
      );
    });
  });

  group('ListDiff with tree rows', () {
    test('rows keyed by node id animate an expand and a collapse', () {
      final tree = DirectoryTree.fromPaths([
        '/r/a/1.txt',
        '/r/a/2.txt',
        '/r/b/3.txt',
        '/r/c.txt',
      ]);
      ({NodeId id, int depth, bool expanded}) rowOf(
        TreeNode<Object?> node,
        Set<NodeId> expanded,
      ) => (
        id: node.id,
        depth: node.depth,
        expanded: expanded.contains(node.id),
      );
      List<({NodeId id, int depth, bool expanded})> rows(Set<NodeId> open) {
        final result = <({NodeId id, int depth, bool expanded})>[];
        void visit(NodeId id) {
          final node = tree[id]!;
          result.add(rowOf(node, open));
          if (open.contains(id)) {
            for (final child in tree.childrenOf(id)) {
              visit(child.id);
            }
          }
        }

        tree.roots.forEach(visit);
        return result;
      }

      final r = tree.idOf('/r')!;
      final a = tree.idOf('/r/a')!;
      final collapsed = rows({r});
      final expanded = rows({r, a});
      final diff = ListDiff.compute(
        collapsed,
        expanded,
        keyOf: (row) => row.id,
      );
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, [2, 3]);
      expect(diff.changedIndices, [1], reason: 'the /r/a row now expanded');
      expect(_apply(collapsed, expanded, diff, (row) => row.id), [
        for (final row in expanded) row.id,
      ]);

      final back = ListDiff.compute(
        expanded,
        collapsed,
        keyOf: (row) => row.id,
      );
      expect(back.removedIndices, [3, 2]);
      expect(back.insertedIndices, isEmpty);
      expect(back.changedIndices, [1]);
    });
  });

  group('ListDiff value semantics', () {
    test('equal diffs are == with equal hashCode', () {
      final a = _diff(const ['a', 'b', 'c'], const ['c', 'a']);
      final b = _diff(const ['x', 'y', 'z'], const ['z', 'x']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(_diff(const ['a'], const ['b'])));
    });

    test('index lists are unmodifiable', () {
      final diff = _diff(const ['a', 'b'], const ['b', 'c']);
      expect(() => diff.removedIndices.add(0), throwsUnsupportedError);
      expect(() => diff.insertedIndices.add(0), throwsUnsupportedError);
      expect(() => diff.changedIndices.add(0), throwsUnsupportedError);
    });

    test('toString lists the three index lists', () {
      expect(
        _diff(const ['a', 'b', 'c'], const ['x', 'a', 'c']).toString(),
        'ListDiff(removed: [1], inserted: [0], changed: [])',
      );
    });
  });
}
