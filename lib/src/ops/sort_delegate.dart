// lib/src/ops/sort_delegate.dart
import 'package:directory_tree/src/models/tree_data.dart';
import 'package:directory_tree/src/models/tree_node.dart';

/// Controls how children of a folder are ordered during flattening.
///
/// Implement this interface to define custom sorting logic (e.g., sort by date,
/// size, or file type priority). Pass your implementation to [SortedFlattenStrategy].
///
/// ### Contract
/// *   **Stability:** Implementations should be stable (preserve insertion order
///     for equal elements) to prevent UI jitter during re-renders.
/// *   **Performance:** This is called once per folder during flatten; avoid
///     expensive operations in [sortChildIds].
abstract class SortDelegate {
  /// Abstract constant constructor.
  const SortDelegate();

  /// Return an ordered list of child ids for `parentId`.
  List<String> sortChildIds(TreeData data, String parentId);
}

/// A standard sorter: folders first, then files, sorted alphabetically.
///
/// Comparison is case-insensitive (`toLowerCase`). When names are equal,
/// ties are broken by node ID to ensure deterministic ordering.
class AlphaSortDelegate extends SortDelegate {
  /// Creates a standard alphabetical sort delegate.
  const AlphaSortDelegate();

  @override
  List<String> sortChildIds(TreeData data, String parentId) {
    final parent = data.nodes[parentId];
    if (parent == null) return const <String>[];

    final byName = List<String>.from(parent.childIds);
    int cmp(String aId, String bId) {
      final a = data.nodes[aId]!;
      final b = data.nodes[bId]!;
      if (a.type != b.type) return a.type == NodeType.folder ? -1 : 1;
      final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (n != 0) return n;
      return a.id.compareTo(b.id);
    }

    byName.sort(cmp);
    return byName;
  }
}
