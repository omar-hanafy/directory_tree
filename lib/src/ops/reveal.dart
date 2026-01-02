// lib/src/ops/reveal.dart
import 'package:directory_tree/src/models/tree_data.dart';
import 'package:directory_tree/src/models/tree_node.dart';

/// Finds the sequence of parent nodes leading to [nodeId].
///
/// Use this to auto-expand the tree to show a specific file.
/// Returns the chain of IDs starting from the root.
List<String> ancestorChain(TreeData data, String nodeId) {
  final chain = <String>[];
  TreeNode? current = data.nodes[nodeId];
  while (current != null && current.parentId.isNotEmpty) {
    chain.insert(0, current.id);
    current = data.nodes[current.parentId];
  }
  if (current != null) {
    chain.insert(0, current.id);
  }
  return chain;
}

/// Searches for a node with the exact virtual path.
///
/// Use this to locate nodes when you only have a path string (e.g., from a URL or saved state).
/// Returns `null` if no node matches the exact [virtualPath].
String? findByVirtualPath(TreeData data, String virtualPath) {
  if (virtualPath.isEmpty) return null;
  for (final entry in data.nodes.entries) {
    if (entry.value.virtualPath == virtualPath) {
      return entry.key;
    }
  }
  return null;
}
