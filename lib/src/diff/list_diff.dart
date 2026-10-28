import 'package:meta/meta.dart';

/// The removals, insertions, and in-place changes that turn one keyed list
/// into another.
///
/// Use it to animate a list that is rebuilt from scratch, such as the rows
/// of a flattened tree after a folder is expanded or a filter changes. Each
/// item has a key (for example a node id); items keep their identity by key
/// across the two lists. [compute] keeps the longest run of items whose keys
/// appear in the same relative order in both lists (a longest increasing
/// subsequence), and reports every other item as removed from the old list
/// and inserted into the new one. A moved item is therefore one removal plus
/// one insertion.
///
/// The indices follow the protocol of Flutter's `AnimatedList` and
/// `SliverAnimatedList`: starting from a copy of the old list, call
/// `removeAt(i)` for each index of [removedIndices] in order, then
/// `insert(i, after[i])` for each index of [insertedIndices] in order. The
/// result has the same keys, in the same order, as the new list:
///
/// ```dart
/// final diff = ListDiff.compute(oldRows, newRows, keyOf: (row) => row.id);
/// final list = listKey.currentState!;
/// for (final index in diff.removedIndices) {
///   final row = oldRows[index];
///   list.removeItem(index, (context, animation) => buildRow(row, animation));
/// }
/// for (final index in diff.insertedIndices) {
///   list.insertItem(index);
/// }
/// // Rows in diff.changedIndices kept their place but have new content;
/// // rebuilding the list with newRows (setState) refreshes them.
/// ```
///
/// A [ListDiff] is an immutable value with value equality.
@immutable
final class ListDiff {
  ListDiff._(
    List<int> removedIndices,
    List<int> insertedIndices,
    List<int> changedIndices,
  ) : removedIndices = List<int>.unmodifiable(removedIndices),
      insertedIndices = List<int>.unmodifiable(insertedIndices),
      changedIndices = List<int>.unmodifiable(changedIndices);

  /// Computes the diff from [before] to [after], matching items by the key
  /// that [keyOf] returns.
  ///
  /// Keys are compared with `==` and `hashCode`, so they must be valid map
  /// keys (ids, strings, records of those). An item whose key is in both
  /// lists is kept when it belongs to the longest subsequence of keys that
  /// appears in the same relative order in both lists; otherwise it is
  /// removed and re-inserted. Since only the maximal such subsequence is
  /// kept, the number of removals (and of insertions) is the minimum
  /// possible for a diff that only removes and inserts. When several
  /// subsequences have that maximal length, the choice is deterministic.
  ///
  /// [equals] decides whether a kept item changed: kept items for which
  /// `equals(beforeItem, afterItem)` is false are listed in
  /// [changedIndices]. It defaults to `==`. It is called once per kept item
  /// and never for removed or inserted items.
  ///
  /// Applying the result: on a copy of [before], call `removeAt` for each
  /// index of [removedIndices] in order, then insert `after[i]` at index `i`
  /// for each `i` of [insertedIndices] in order. The copy then has the same
  /// keys as [after], in the same order.
  ///
  /// Empty lists are valid: from an empty list everything is inserted; to
  /// an empty list everything is removed.
  ///
  /// Throws an [ArgumentError] when a key occurs more than once within
  /// [before] or within [after]; the message names the key, the list, and
  /// both indices.
  ///
  /// Runs in O(n + m) when the two key sequences are equal (including when
  /// [before] and [after] are the same list), and in O((n + m) log(n + m))
  /// otherwise, plus one [keyOf] call per item; n and m are the list
  /// lengths.
  static ListDiff compute<E, K>(
    List<E> before,
    List<E> after, {
    required K Function(E item) keyOf,
    bool Function(E before, E after)? equals,
  }) {
    final isEqual = equals ?? _defaultEquals;
    final n = before.length;
    final m = after.length;

    final beforeKeys = List<K>.generate(n, (i) => keyOf(before[i]));
    _indexKeys(beforeKeys, 'before');
    final List<K> afterKeys;
    if (identical(before, after)) {
      afterKeys = beforeKeys;
    } else {
      afterKeys = List<K>.generate(m, (i) => keyOf(after[i]));
    }

    // Fast path: same key sequence. Everything is kept in place, so only
    // changes are possible. Duplicates in [after] are already ruled out by
    // the check on [before].
    if (n == m && _sameKeys(beforeKeys, afterKeys)) {
      final changed = <int>[
        for (var i = 0; i < n; i++)
          if (!isEqual(before[i], after[i])) i,
      ];
      return ListDiff._(const <int>[], const <int>[], changed);
    }

    final afterIndexByKey = _indexKeys(afterKeys, 'after');

    // For each before item whose key is also in after, the after index it
    // maps to, in before order. Kept items are a longest increasing
    // subsequence of these after indices.
    final sequence = <int>[];
    final sequenceBeforeIndex = <int>[];
    for (var i = 0; i < n; i++) {
      final afterIndex = afterIndexByKey[beforeKeys[i]];
      if (afterIndex != null) {
        sequence.add(afterIndex);
        sequenceBeforeIndex.add(i);
      }
    }
    final kept = _longestIncreasingSubsequence(sequence);

    final keptBefore = List<bool>.filled(n, false);
    final keptAfter = List<bool>.filled(m, false);
    final changed = <int>[];
    for (final position in kept) {
      final beforeIndex = sequenceBeforeIndex[position];
      final afterIndex = sequence[position];
      keptBefore[beforeIndex] = true;
      keptAfter[afterIndex] = true;
      // [kept] is ascending in after index, so [changed] is too.
      if (!isEqual(before[beforeIndex], after[afterIndex])) {
        changed.add(afterIndex);
      }
    }

    final removed = <int>[
      for (var i = n - 1; i >= 0; i--)
        if (!keptBefore[i]) i,
    ];
    final inserted = <int>[
      for (var i = 0; i < m; i++)
        if (!keptAfter[i]) i,
    ];
    return ListDiff._(removed, inserted, changed);
  }

  /// Indices into the old list of the items to remove, in descending order.
  ///
  /// Descending order means removing them one by one with `removeAt` never
  /// shifts an index that is still to be removed. The list is unmodifiable.
  final List<int> removedIndices;

  /// Indices into the new list of the items to insert, in ascending order.
  ///
  /// Apply them after all removals: inserting `after[i]` at `i` for each
  /// index in this order rebuilds the new list. The list is unmodifiable.
  final List<int> insertedIndices;

  /// Indices into the new list of kept items whose content changed, in
  /// ascending order.
  ///
  /// A kept item is listed when the `equals` function given to [compute]
  /// returned false for its old and new versions. These items keep their
  /// position, so a UI only needs to rebuild them, not animate them. The
  /// list is unmodifiable.
  final List<int> changedIndices;

  /// Whether the two lists had the same keys in the same order and no kept
  /// item changed: [removedIndices], [insertedIndices], and
  /// [changedIndices] are all empty.
  bool get isEmpty =>
      removedIndices.isEmpty &&
      insertedIndices.isEmpty &&
      changedIndices.isEmpty;

  /// Whether [other] is a [ListDiff] with equal index lists.
  ///
  /// Runs in O(total number of indices).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListDiff &&
          _listEquals(other.removedIndices, removedIndices) &&
          _listEquals(other.insertedIndices, insertedIndices) &&
          _listEquals(other.changedIndices, changedIndices);

  /// A hash of the three index lists, computed once and cached.
  @override
  late final int hashCode = Object.hash(
    Object.hashAll(removedIndices),
    Object.hashAll(insertedIndices),
    Object.hashAll(changedIndices),
  );

  @override
  String toString() =>
      'ListDiff(removed: $removedIndices, inserted: $insertedIndices, '
      'changed: $changedIndices)';
}

bool _defaultEquals(Object? a, Object? b) => a == b;

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameKeys<K>(List<K> a, List<K> b) {
  if (identical(a, b)) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Maps each key to its index, throwing on the first duplicate.
Map<K, int> _indexKeys<K>(List<K> keys, String listName) {
  final indexByKey = <K, int>{};
  for (var i = 0; i < keys.length; i++) {
    final key = keys[i];
    final previous = indexByKey[key];
    if (previous != null) {
      throw ArgumentError(
        'Duplicate key $key in $listName at indices $previous and $i; '
        'keys must be unique within each list.',
        listName,
      );
    }
    indexByKey[key] = i;
  }
  return indexByKey;
}

/// Positions in [sequence] of one longest strictly increasing subsequence,
/// in ascending order.
///
/// Patience sorting with predecessor links: `tails[k]` is the position of
/// the smallest possible last value of an increasing run of length `k + 1`
/// seen so far. Each value binary-searches its run length, so this runs in
/// O(n log n) without recursion. Ties cannot occur because [sequence] holds
/// distinct after indices.
List<int> _longestIncreasingSubsequence(List<int> sequence) {
  final length = sequence.length;
  if (length == 0) return const <int>[];
  final tails = <int>[];
  final previous = List<int>.filled(length, -1);
  for (var i = 0; i < length; i++) {
    final value = sequence[i];
    if (tails.isEmpty || sequence[tails.last] < value) {
      previous[i] = tails.isEmpty ? -1 : tails.last;
      tails.add(i);
      continue;
    }
    // First run whose last value is >= value.
    var low = 0;
    var high = tails.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (sequence[tails[middle]] < value) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    previous[i] = low == 0 ? -1 : tails[low - 1];
    tails[low] = i;
  }
  final result = List<int>.filled(tails.length, 0);
  var position = tails.last;
  for (var k = tails.length - 1; k >= 0; k--) {
    result[k] = position;
    position = previous[position];
  }
  return result;
}
