import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
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

/// Whether assertions run on this platform and mode; duplicates that the
/// common prefix or suffix keeps in place are only detected then.
bool get _assertsEnabled {
  var enabled = false;
  assert(enabled = true);
  return enabled;
}

/// An item with a key and a version, compared by identity, so tests control
/// which items are the identical object in both lists.
final class _Item {
  _Item(this.key, [this.version = 0]);

  final String key;
  final int version;

  @override
  String toString() => '$key@$version';
}

/// Diffs [before] and [after] by key with `equals` comparing versions, and
/// checks the result against the apply contract.
ListDiff _diffItems(List<_Item> before, List<_Item> after) {
  final diff = ListDiff.compute(
    before,
    after,
    keyOf: (item) => item.key,
    equals: (a, b) => a.version == b.version,
  );
  _expectWellFormed(diff, before.length, after.length);
  expect(_apply(before, after, diff, (item) => item.key), [
    for (final item in after) item.key,
  ], reason: 'apply contract for $before -> $after: $diff');
  return diff;
}

List<_Item> _items(String keys) => [
  for (final key in keys.split('')) _Item(key),
];

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

    test(
      'duplicates in identical key sequences throw only with assertions',
      () {
        // Equal key sequences are one long common prefix, which is kept by
        // position without hashing.
        final list = ['x', 'x'];
        if (_assertsEnabled) {
          expect(() => _diff(list, list), throwsArgumentError);
          expect(() => _diff(['x', 'x'], ['x', 'x']), throwsArgumentError);
        } else {
          expect(_diff(list, list).isEmpty, isTrue);
          expect(_diff(['x', 'x'], ['x', 'x']).isEmpty, isTrue);
        }
      },
    );

    test('a duplicate in the middle of before is found without assertions', () {
      // 'a' also occurs in the common prefix; the middle check reports the
      // two middle occurrences, which proves it ran before the debug-only
      // check of the whole list (that one would report indices 0 and 2).
      expect(
        () => _diff(const ['a', 'b', 'a', 'a'], const ['a', 'x']),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'before')
              .having((e) => '${e.message}', 'message', contains('2 and 3')),
        ),
      );
    });

    test('a duplicate in the middle of after is found without assertions', () {
      expect(
        () => _diff(const ['a', 'b', 'z'], const ['a', 'a', 'y', 'y', 'z']),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'after')
              .having((e) => '${e.message}', 'message', contains('2 and 3')),
        ),
      );
    });

    test('a duplicate among removed middle items is found', () {
      expect(
        () => _diff(const ['a', 'x', 'y', 'x', 'b'], const ['a', 'b']),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'before')
              .having((e) => '${e.message}', 'message', contains('1 and 3')),
        ),
      );
    });

    test('a duplicate among inserted middle items is found', () {
      expect(
        () => _diff(const ['a', 'b'], const ['a', 'x', 'y', 'x', 'b']),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'after')
              .having((e) => '${e.message}', 'message', contains('1 and 3')),
        ),
      );
    });

    test('a duplicate among matched middle items is found', () {
      // Both 'k's of before map to the single 'k' in the middle of after.
      expect(
        () => _diff(
          const ['a', 'k', 'b', 'k', 'c'],
          const ['a', 'b', 'k', 'x', 'c'],
        ),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'before')
              .having((e) => '${e.message}', 'message', contains('1 and 3')),
        ),
      );
    });

    test(
      'duplicates kept by the prefix or suffix throw only with assertions',
      () {
        final cases = <(List<String>, List<String>, String)>[
          // Both copies in the common prefix.
          (const ['x', 'x', 'y'], const ['x', 'x', 'z'], 'before'),
          // Both copies in the common suffix.
          (const ['y', 'x', 'x'], const ['z', 'x', 'x'], 'before'),
          // One copy in the prefix, one in the middle of before.
          (const ['a', 'b', 'a'], const ['a', 'c'], 'before'),
          // One copy in the middle of after, one in the suffix.
          (const ['a', 'z'], const ['b', 'z', 'z'], 'after'),
        ];
        for (final (before, after, list) in cases) {
          if (_assertsEnabled) {
            expect(
              () => _diff(before, after),
              throwsA(isA<ArgumentError>().having((e) => e.name, 'name', list)),
              reason: '$before -> $after',
            );
          } else {
            // Unspecified, but it must not throw.
            _diff(before, after);
          }
        }
      },
    );

    test('equal items with distinct keys are fine', () {
      final before = [(id: 1, v: 'same'), (id: 2, v: 'same')];
      final after = [(id: 2, v: 'same'), (id: 1, v: 'same')];
      final diff = ListDiff.compute(before, after, keyOf: (item) => item.id);
      expect(diff.removedIndices.length, 1);
      expect(diff.insertedIndices.length, 1);
    });
  });

  group('ListDiff.compute common prefix and suffix', () {
    test('a prefix only: items appended or dropped at the end', () {
      var diff = _diffItems(_items('abc'), _items('abcde'));
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, [3, 4]);

      diff = _diffItems(_items('abcd'), _items('ab'));
      expect(diff.removedIndices, [3, 2]);
      expect(diff.insertedIndices, isEmpty);
    });

    test('a suffix only: items prepended or dropped at the start', () {
      var diff = _diffItems(_items('cd'), _items('abcd'));
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, [0, 1]);

      diff = _diffItems(_items('abcd'), _items('cd'));
      expect(diff.removedIndices, [1, 0]);
      expect(diff.insertedIndices, isEmpty);
    });

    test('a prefix and a suffix around an inserted or removed block', () {
      var diff = _diffItems(_items('abef'), _items('abcdef'));
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, [2, 3]);

      diff = _diffItems(_items('abcdef'), _items('abef'));
      expect(diff.removedIndices, [3, 2]);
      expect(diff.insertedIndices, isEmpty);
    });

    test('a prefix and a suffix around a block that is replaced', () {
      final diff = _diffItems(_items('abxyef'), _items('abuvwef'));
      expect(diff.removedIndices, [3, 2]);
      expect(diff.insertedIndices, [2, 3, 4]);
    });

    test('a prefix and a suffix around a move in the middle', () {
      final diff = _diffItems(_items('abcdef'), _items('abdcef'));
      expect(diff.removedIndices, [2]);
      expect(diff.insertedIndices, [3]);
      expect(diff.changedIndices, isEmpty);
    });

    test('an empty middle: equal key sequences only report changes', () {
      final before = [_Item('a'), _Item('b'), _Item('c'), _Item('d')];
      final after = [_Item('a', 1), _Item('b'), _Item('c'), _Item('d', 1)];
      final diff = _diffItems(before, after);
      expect(diff.removedIndices, isEmpty);
      expect(diff.insertedIndices, isEmpty);
      expect(diff.changedIndices, [0, 3]);
    });

    test('all-equal lists of identical or equal items give empty diffs', () {
      final items = _items('abcdef');
      expect(_diffItems(items, items).isEmpty, isTrue);
      expect(_diffItems(items, List.of(items)).isEmpty, isTrue);
      expect(_diffItems(items, _items('abcdef')).isEmpty, isTrue);
    });

    test('one list being a prefix or suffix of the other', () {
      expect(_diffItems(_items('a'), _items('abc')).insertedIndices, [1, 2]);
      expect(_diffItems(_items('abc'), _items('a')).removedIndices, [2, 1]);
      expect(_diffItems(_items('c'), _items('abc')).insertedIndices, [0, 1]);
      expect(_diffItems(_items('abc'), _items('c')).removedIndices, [1, 0]);
      expect(_diffItems(<_Item>[], _items('ab')).insertedIndices, [0, 1]);
      expect(_diffItems(_items('ab'), <_Item>[]).removedIndices, [1, 0]);
    });

    test('single-item changes at every position', () {
      const keys = 'abcde';
      for (var i = 0; i <= keys.length; i++) {
        final inserted = '${keys.substring(0, i)}X${keys.substring(i)}';
        var diff = _diffItems(_items(keys), _items(inserted));
        expect(diff.insertedIndices, [i], reason: 'insert at $i');
        expect(diff.removedIndices, isEmpty);
      }
      for (var i = 0; i < keys.length; i++) {
        final removed = keys.substring(0, i) + keys.substring(i + 1);
        var diff = _diffItems(_items(keys), _items(removed));
        expect(diff.removedIndices, [i], reason: 'remove at $i');
        expect(diff.insertedIndices, isEmpty);

        final replaced = '${keys.substring(0, i)}X${keys.substring(i + 1)}';
        diff = _diffItems(_items(keys), _items(replaced));
        expect(diff.removedIndices, [i], reason: 'replace at $i');
        expect(diff.insertedIndices, [i], reason: 'replace at $i');

        final before = _items(keys);
        final after = [
          for (var k = 0; k < before.length; k++)
            k == i ? _Item(before[k].key, 1) : before[k],
        ];
        diff = _diffItems(before, after);
        expect(diff.removedIndices, isEmpty);
        expect(diff.insertedIndices, isEmpty);
        expect(diff.changedIndices, [i], reason: 'change at $i');
      }
    });

    test('changes and equals calls in the prefix, middle, and suffix', () {
      final a = _Item('a');
      final c = _Item('c');
      final before = [a, _Item('b'), _Item('x'), c, _Item('d')];
      final after = [a, _Item('b', 1), _Item('y'), c, _Item('d', 1)];
      final calls = <String>[];
      final diff = ListDiff.compute(
        before,
        after,
        keyOf: (item) => item.key,
        equals: (x, y) {
          calls.add('${x.key}=${y.key}');
          return x.version == y.version;
        },
      );
      expect(diff.removedIndices, [2]);
      expect(diff.insertedIndices, [2]);
      expect(diff.changedIndices, [1, 4]);
      expect(calls, ['a=a', 'b=b', 'c=c', 'd=d']);
    });
  });

  group('ListDiff.compute keyOf calls', () {
    test(
      'keys of identical items at prefix and suffix positions are skipped',
      () {
        final shared = _items('abcdef');
        final before = [...shared.take(3), _Item('x'), ...shared.skip(3)];
        final after = [
          ...shared.take(3),
          _Item('y'),
          _Item('z'),
          ...shared.skip(3),
        ];
        final calls = <_Item, int>{};
        final diff = ListDiff.compute(
          before,
          after,
          keyOf: (item) {
            calls[item] = (calls[item] ?? 0) + 1;
            return item.key;
          },
        );
        expect(diff.removedIndices, [3]);
        expect(diff.insertedIndices, [3, 4]);
        // The uniqueness check of debug builds computes every key once more,
        // and a shared item is in both lists.
        final extra = _assertsEnabled ? 1 : 0;
        for (final item in shared) {
          expect(calls[item] ?? 0, 2 * extra, reason: '$item');
        }
        for (final item in [before[3], after[3], after[4]]) {
          expect(calls[item], 1 + extra, reason: '$item');
        }
      },
    );

    test('keyOf runs at most once per item outside the debug check', () {
      final random = Random(99);
      final extra = _assertsEnabled ? 1 : 0;
      for (var round = 0; round < 500; round++) {
        final keys = _randomKeys(random, random.nextInt(20), 30);
        final afterKeys = _edit(random, keys, 30, random.nextInt(5));
        // Distinct objects, so every call is attributed to one list.
        final before = [for (final key in keys) _Item('$key')];
        final after = [for (final key in afterKeys) _Item('$key')];
        final calls = <_Item, int>{};
        ListDiff.compute(
          before,
          after,
          keyOf: (item) {
            calls[item] = (calls[item] ?? 0) + 1;
            return item.key;
          },
        );
        for (final count in calls.values) {
          expect(count, lessThanOrEqualTo(1 + extra), reason: '$keys');
        }
      }
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

    test(
      'apply contract and minimality around shared prefixes and suffixes',
      () {
        final random = Random(4242);
        const pool = 60;
        for (var round = 0; round < 2000; round++) {
          final beforeKeys = _randomKeys(random, random.nextInt(30), pool);
          final prefixLength = random.nextInt(beforeKeys.length + 1);
          final suffixLength = random.nextInt(
            beforeKeys.length - prefixLength + 1,
          );
          final suffixStart = beforeKeys.length - suffixLength;
          // Fresh keys from _edit start at [pool], so they never collide.
          final middle = _edit(
            random,
            beforeKeys.sublist(prefixLength, suffixStart),
            pool,
            random.nextInt(6),
          );
          final afterKeys = [
            ...beforeKeys.sublist(0, prefixLength),
            ...middle,
            ...beforeKeys.sublist(suffixStart),
          ];
          final before = [for (final key in beforeKeys) _Item('$key')];
          final beforeIndexOf = {
            for (var i = 0; i < beforeKeys.length; i++) beforeKeys[i]: i,
          };
          // A key that is in both lists carries over as the identical item,
          // an equal copy, or a changed copy.
          final after = [
            for (final key in afterKeys)
              switch (beforeIndexOf[key]) {
                null => _Item('$key'),
                final index => switch (random.nextInt(3)) {
                  0 => before[index],
                  1 => _Item('$key'),
                  _ => _Item('$key', 1),
                },
              },
          ];
          final diff = _diffItems(before, after);
          final reason = 'before: $before, after: $after, diff: $diff';
          expect(
            before.length - diff.removedIndices.length,
            _oracleKeptCount(beforeKeys, afterKeys),
            reason: reason,
          );
          final inserted = diff.insertedIndices.toSet();
          expect(diff.changedIndices, [
            for (var j = 0; j < after.length; j++)
              if (!inserted.contains(j) && after[j].version != 0) j,
          ], reason: reason);
        }
      },
    );

    test('collapsing or expanding one directory of tree rows is one block', () {
      final tree = DirectoryTree.fromPaths([
        for (var a = 0; a < 5; a++)
          for (var b = 0; b < 4; b++)
            for (var c = 0; c < 3; c++) '/r/d$a/e$b/f$c.txt',
      ]);
      final rows = tree.flatten();
      final target = tree.idOf('/r/d2/e1')!;
      final index = rows.indexOfNode(target);
      final collapsed = rows.collapseNode(target);
      final hidden = rows.length - collapsed.length;
      expect(hidden, 3);

      final collapse = ListDiff.compute(
        rows,
        collapsed,
        keyOf: (row) => row.id,
      );
      expect(collapse.removedIndices, [
        for (var i = index + hidden; i > index; i--) i,
      ]);
      expect(collapse.insertedIndices, isEmpty);
      expect(collapse.changedIndices, [index], reason: 'now collapsed');

      final expand = ListDiff.compute(collapsed, rows, keyOf: (row) => row.id);
      expect(expand.removedIndices, isEmpty);
      expect(expand.insertedIndices, [
        for (var i = index + 1; i <= index + hidden; i++) i,
      ]);
      expect(expand.changedIndices, [index], reason: 'now expanded');
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
