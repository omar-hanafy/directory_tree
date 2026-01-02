// lib/src/ops/selection_utils.dart
import 'package:directory_tree/src/models/tree_data.dart';
import 'package:directory_tree/src/models/tree_node.dart';

/// Represents the tri-state selection status of a folder.
enum FolderSelection {
  /// No descendants are selected.
  none,

  /// Some (but not all) descendants are selected.
  partial,

  /// All descendants are selected.
  all,
}

/// Determines if a folder should be checked, unchecked, or indeterminate based on its descendants.
///
/// ### Behavior
/// *   **Recursion:** Traverses the entire subtree via an iterative DFS.
/// *   **Tri-State:** Returns [FolderSelection.partial] if only some descendants are selected.
///
/// ### Performance
/// This performs a full traversal of all descendants. For trees with >10k nodes,
/// consider caching selection counts or computing them incrementally.
FolderSelection folderSelection({
  required TreeData data,
  required Set<String> selectedIds,
  required String folderId,
}) {
  final root = data.nodes[folderId];
  if (root == null) return FolderSelection.none;
  var totalFiles = 0;
  var selectedFiles = 0;
  final stack = <String>[folderId];

  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    final node = data.nodes[id];
    if (node == null) continue;
    if (node.type == NodeType.file) {
      totalFiles++;
      if (selectedIds.contains(id)) {
        selectedFiles++;
      }
      continue;
    }
    stack.addAll(node.childIds);
  }

  if (totalFiles == 0 || selectedFiles == 0) return FolderSelection.none;
  if (selectedFiles == totalFiles) return FolderSelection.all;
  return FolderSelection.partial;
}
