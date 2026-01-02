import 'package:directory_tree/src/ops/visible_node.dart';

/// Represents the delta required to transform one list of nodes into another.
///
/// This is used for efficient UI updates (e.g., Flutter's `AnimatedList`).
/// It provides indices to remove (in descending order) and indices to insert
/// (in ascending order).
class ListDiff {
  /// Creates a diff describing changes between two lists.
  const ListDiff({
    required this.removeIndicesDesc,
    required this.insertIndicesAsc,
  });

  /// Indices to remove from the previous list, sorted descending.
  final List<int> removeIndicesDesc;

  /// Indices to insert into the new list, sorted ascending.
  final List<int> insertIndicesAsc;

  /// Returns true if no changes are required.
  bool get isNoop => removeIndicesDesc.isEmpty && insertIndicesAsc.isEmpty;
}

/// Computes the difference between two flat lists to enable smooth UI animations using [ListDiff].
///
/// ### Behavior
/// *   **Minimality:** Uses the Longest Increasing Subsequence (LIS) algorithm to
///     keep as many rows stable as possible.
/// *   **Animation:** Returns indices sorted specifically for sequential processing
///     (removals descending, insertions ascending) to avoid index shifting bugs.
ListDiff diffVisibleNodes(List<VisibleNode> before, List<VisibleNode> after) {
  if (identical(before, after) ||
      (before.length == after.length && _sameIds(before, after))) {
    return const ListDiff(
      removeIndicesDesc: <int>[],
      insertIndicesAsc: <int>[],
    );
  }

  final afterIndexById = <String, int>{
    for (var i = 0; i < after.length; i++) after[i].id: i,
  };

  // Sequence of "after indices" that correspond to items in 'before'.
  final seq = <int>[];
  for (var i = 0; i < before.length; i++) {
    final idx = afterIndexById[before[i].id];
    if (idx != null) {
      seq.add(idx);
    }
  }

  // Longest Increasing Subsequence over 'seq' (classic patience algorithm).
  final lisPositions = _lisIndices(seq); // positions within 'seq'
  final keptAfterIndexSet = <int>{for (final pos in lisPositions) seq[pos]};

  // Removes = items from 'before' not in LIS.
  final removeIndices = <int>[];
  for (var beforeIdx = 0; beforeIdx < before.length; beforeIdx++) {
    final id = before[beforeIdx].id;
    final ai = afterIndexById[id];
    if (ai == null || !keptAfterIndexSet.contains(ai)) {
      removeIndices.add(beforeIdx);
    }
  }
  removeIndices.sort((a, b) => b.compareTo(a)); // DESC

  // Inserts = items from 'after' not in LIS.
  final insertIndices = <int>[];
  for (var afterIdx = 0; afterIdx < after.length; afterIdx++) {
    if (!keptAfterIndexSet.contains(afterIdx)) {
      insertIndices.add(afterIdx);
    }
  }
  // Inserts already in ascending pass.

  return ListDiff(
    removeIndicesDesc: removeIndices,
    insertIndicesAsc: insertIndices,
  );
}

bool _sameIds(List<VisibleNode> a, List<VisibleNode> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}

/// Patience/LIS returning **indices into `seq`** that form the LIS.
List<int> _lisIndices(List<int> seq) {
  if (seq.isEmpty) return const <int>[];

  final tails = <int>[]; // values
  final tailsPos = <int>[]; // positions in seq for those tails
  final prev = List<int>.filled(seq.length, -1);

  int lowerBound(List<int> a, int x) {
    var lo = 0;
    var hi = a.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (a[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  for (var i = 0; i < seq.length; i++) {
    final x = seq[i];
    final pos = lowerBound(tails, x);
    if (pos == tails.length) {
      tails.add(x);
      tailsPos.add(i);
    } else {
      tails[pos] = x;
      tailsPos[pos] = i;
    }
    prev[i] = pos > 0 ? tailsPos[pos - 1] : -1;
  }

  // Reconstruct indices of seq that form the LIS.
  var k = tailsPos.isEmpty ? -1 : tailsPos.last;
  final lis = <int>[];
  while (k != -1) {
    lis.add(k);
    k = prev[k];
  }
  return lis.reversed.toList(growable: false);
}
