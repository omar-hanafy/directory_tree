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
  /// Keys are compared with `==`, and keys outside the common prefix and
  /// suffix (see below) are also hashed, so they must be valid map keys
  /// (ids, strings, records of those). An item whose key is in both lists
  /// is kept when it belongs to the longest subsequence of keys that
  /// appears in the same relative order in both lists; otherwise it is
  /// removed and re-inserted. Since only the maximal such subsequence is
  /// kept, the number of removals (and of insertions) is the minimum
  /// possible for a diff that only removes and inserts. When several
  /// subsequences have that maximal length, the choice is deterministic.
  ///
  /// [equals] decides whether a kept item changed: kept items for which
  /// `equals(beforeItem, afterItem)` is false are listed in
  /// [changedIndices]. It defaults to `==`. It is called once per kept item,
  /// in ascending order of the item's index in [after], and never for
  /// removed or inserted items.
  ///
  /// Applying the result: on a copy of [before], call `removeAt` for each
  /// index of [removedIndices] in order, then insert `after[i]` at index `i`
  /// for each `i` of [insertedIndices] in order. The copy then has the same
  /// keys as [after], in the same order.
  ///
  /// Empty lists are valid: from an empty list everything is inserted; to
  /// an empty list everything is removed.
  ///
  /// ## How the lists are matched
  ///
  /// The common prefix (the longest run of leading positions whose keys are
  /// equal in both lists) and then the common suffix (the longest run of
  /// trailing positions whose keys are equal, not overlapping the prefix)
  /// are kept in place by comparing keys pairwise, without hashing. Only
  /// the items between them, the middle region of each list, are hashed
  /// and matched with a longest increasing subsequence. A typical view
  /// update, such as the rows after expanding or collapsing one directory,
  /// changes one contiguous block, so only that block is hashed.
  ///
  /// ## Duplicate keys
  ///
  /// Keys must be unique within [before] and within [after]. Throws an
  /// [ArgumentError] when two items of the middle region of [before], or
  /// two items of the middle region of [after], have equal keys; the
  /// message names the key, the list, and both indices. Equal keys
  /// elsewhere (for example both in the common prefix, or one in the prefix
  /// and one in the middle region) are detected only when assertions are
  /// enabled, as in debug builds, where they throw the same [ArgumentError]
  /// once the middle region has been checked; with assertions disabled such
  /// input yields an unspecified diff.
  ///
  /// ## Cost
  ///
  /// With n and m the list lengths, p and s the lengths of the common
  /// prefix and suffix, and k the number of middle items in both lists
  /// together (`n + m - 2 * (p + s)`), this runs in O(n + m) key
  /// comparisons and [equals] calls plus O(k log k) for the middle region.
  /// [keyOf] is called at most once per item, and not at all for an item
  /// that is the identical object at the same prefix or suffix position of
  /// both lists. When assertions are enabled, the uniqueness check calls
  /// [keyOf] once more per item and hashes every key.
  static ListDiff compute<E, K>(
    List<E> before,
    List<E> after, {
    required K Function(E item) keyOf,
    bool Function(E before, E after)? equals,
  }) {
    final isEqual = equals ?? _defaultEquals;
    final n = before.length;
    final m = after.length;
    final shortest = n < m ? n : m;

    // Common prefix. An item that is the identical object at the same
    // position of both lists has the same key, so its key is not computed:
    // rows rebuilt around one changed block share most row objects with
    // the old rows. The keys of the first mismatching pair are kept, since
    // those items belong to the middle region and keyOf runs once per item.
    late K prefixBeforeKey;
    late K prefixAfterKey;
    var prefixMismatch = false;
    var prefix = 0;
    if (identical(before, after)) {
      prefix = n;
    } else {
      while (prefix < shortest) {
        final beforeItem = before[prefix];
        final afterItem = after[prefix];
        if (!identical(beforeItem, afterItem)) {
          final beforeKey = keyOf(beforeItem);
          final afterKey = keyOf(afterItem);
          if (beforeKey != afterKey) {
            prefixBeforeKey = beforeKey;
            prefixAfterKey = afterKey;
            prefixMismatch = true;
            break;
          }
        }
        prefix++;
      }
    }

    // Common suffix, never overlapping the prefix. It can only run when the
    // prefix scan stopped at a mismatch (otherwise the shorter list is used
    // up), so a position the prefix stopped at reuses that key. When the
    // suffix stops at a mismatch, the keys of that pair, the last middle
    // items, are kept too.
    late K suffixBeforeKey;
    late K suffixAfterKey;
    var suffixMismatch = false;
    var suffix = 0;
    final maxSuffix = shortest - prefix;
    while (suffix < maxSuffix) {
      final beforeIndex = n - 1 - suffix;
      final afterIndex = m - 1 - suffix;
      final beforeItem = before[beforeIndex];
      final afterItem = after[afterIndex];
      if (!identical(beforeItem, afterItem)) {
        final beforeKey = beforeIndex == prefix
            ? prefixBeforeKey
            : keyOf(beforeItem);
        final afterKey = afterIndex == prefix
            ? prefixAfterKey
            : keyOf(afterItem);
        if (beforeKey != afterKey) {
          suffixBeforeKey = beforeKey;
          suffixAfterKey = afterKey;
          suffixMismatch = true;
          break;
        }
      }
      suffix++;
    }

    // The middle regions: before[prefix, beforeEnd) and after[prefix,
    // afterEnd). Keys the scans already computed are reused (the loops
    // below spell this out instead of using closures, which would move the
    // loop counters into a heap context).
    final beforeEnd = n - suffix;
    final afterEnd = m - suffix;

    // Each middle key of [after], mapped to its index. A middle key of
    // [before] that [after] lacks is stored as -1 - (its before index), so
    // a second occurrence in [before] is found by the same lookup.
    final indexByKey = <K, int>{};
    for (var j = prefix; j < afterEnd; j++) {
      final K key;
      if (prefixMismatch && j == prefix) {
        key = prefixAfterKey;
      } else if (suffixMismatch && j == afterEnd - 1) {
        key = suffixAfterKey;
      } else {
        key = keyOf(after[j]);
      }
      final previous = indexByKey[key];
      if (previous != null) throw _duplicateKey(key, 'after', previous, j);
      indexByKey[key] = j;
    }

    // For each middle item of [before] whose key is in the middle of
    // [after], the after index it maps to, in before order. Kept middle
    // items are a longest increasing subsequence of these after indices.
    // claimedBy[j - prefix] is the before index mapped to after index j.
    final afterMiddle = afterEnd - prefix;
    final claimedBy = List<int>.filled(afterMiddle, -1);
    final sequence = <int>[];
    final sequenceBeforeIndex = <int>[];
    for (var i = prefix; i < beforeEnd; i++) {
      final K key;
      if (prefixMismatch && i == prefix) {
        key = prefixBeforeKey;
      } else if (suffixMismatch && i == beforeEnd - 1) {
        key = suffixBeforeKey;
      } else {
        key = keyOf(before[i]);
      }
      final mapped = indexByKey[key];
      if (mapped == null) {
        indexByKey[key] = -1 - i;
      } else if (mapped < 0) {
        throw _duplicateKey(key, 'before', -1 - mapped, i);
      } else {
        final claimed = claimedBy[mapped - prefix];
        if (claimed >= 0) throw _duplicateKey(key, 'before', claimed, i);
        claimedBy[mapped - prefix] = i;
        sequence.add(mapped);
        sequenceBeforeIndex.add(i);
      }
    }

    // The middle regions are free of duplicates; in debug builds, also
    // check the items that the prefix and suffix scans kept by position.
    assert(
      _checkUniqueKeys(before, keyOf, 'before') &&
          (identical(before, after) || _checkUniqueKeys(after, keyOf, 'after')),
      'Keys must be unique within each list.',
    );

    final kept = _longestIncreasingSubsequence(sequence);
    final keptBefore = List<bool>.filled(beforeEnd - prefix, false);
    final keptAfter = List<bool>.filled(afterMiddle, false);

    // [equals] runs once per kept item in ascending after order: prefix,
    // kept middle items ([kept] is ascending in after index), then suffix.
    final changed = <int>[
      for (var i = 0; i < prefix; i++)
        if (!isEqual(before[i], after[i])) i,
    ];
    for (final position in kept) {
      final beforeIndex = sequenceBeforeIndex[position];
      final afterIndex = sequence[position];
      keptBefore[beforeIndex - prefix] = true;
      keptAfter[afterIndex - prefix] = true;
      if (!isEqual(before[beforeIndex], after[afterIndex])) {
        changed.add(afterIndex);
      }
    }
    for (var t = 0; t < suffix; t++) {
      if (!isEqual(before[beforeEnd + t], after[afterEnd + t])) {
        changed.add(afterEnd + t);
      }
    }

    final removed = <int>[
      for (var i = beforeEnd - 1; i >= prefix; i--)
        if (!keptBefore[i - prefix]) i,
    ];
    final inserted = <int>[
      for (var j = prefix; j < afterEnd; j++)
        if (!keptAfter[j - prefix]) j,
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

/// The error for [key] occurring at [previous] and [index] of [listName].
ArgumentError _duplicateKey(
  Object? key,
  String listName,
  int previous,
  int index,
) => ArgumentError(
  'Duplicate key $key in $listName at indices $previous and $index; '
  'keys must be unique within each list.',
  listName,
);

/// Returns true when the keys of [items] are unique; otherwise throws the
/// [ArgumentError] of [_duplicateKey] for the first repeated key.
///
/// Only called from an assert: release builds check just the middle
/// regions, which keeps a diff of one changed block from hashing every key.
bool _checkUniqueKeys<E, K>(
  List<E> items,
  K Function(E item) keyOf,
  String listName,
) {
  final indexByKey = <K, int>{};
  for (var i = 0; i < items.length; i++) {
    final key = keyOf(items[i]);
    final previous = indexByKey[key];
    if (previous != null) throw _duplicateKey(key, listName, previous, i);
    indexByKey[key] = i;
  }
  return true;
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
