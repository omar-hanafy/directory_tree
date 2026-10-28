import 'package:directory_tree/src/diff/list_diff.dart';
import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:directory_tree/src/tree/tree_options.dart';
import 'package:meta/meta.dart';

/// The nodes added, removed, and changed between two [DirectoryTree]s,
/// matched by [NodeId].
///
/// Use it to react to a rebuilt tree, for example after a rescan: drop
/// cached state for [removed] ids, load metadata for [added] ids, and
/// refresh the widgets of [changed] ids. For the order of visible rows (what
/// an animated list needs), diff the rows with [ListDiff] instead.
///
/// Nodes are matched by id, so both trees should use the same [PathPolicy]:
/// under different policies the same path can have different ids (a
/// case-insensitive tree lowercases them) and shows up as removed and added.
///
/// A [TreeDiff] is an immutable value with value equality.
@immutable
final class TreeDiff {
  TreeDiff._(List<NodeId> added, List<NodeId> removed, List<NodeId> changed)
    : added = List<NodeId>.unmodifiable(added),
      removed = List<NodeId>.unmodifiable(removed),
      changed = List<NodeId>.unmodifiable(changed);

  /// Compares [before] with [after] node by node.
  ///
  /// A node is added when its id is only in [after], removed when its id is
  /// only in [before], and changed when its id is in both but its kind,
  /// [TreeNode.path] (including a different spelling under a
  /// case-insensitive policy), [TreeNode.label], [TreeNode.entry] (path,
  /// kind, or data, compared with `==`), or [TreeNode.parent]
  /// differs. A node becoming or ceasing to be top level is a parent change.
  ///
  /// Not counted as a change on their own:
  /// * a directory's child list: new or removed children appear in [added]
  ///   or [removed], and a reordering of siblings is not reported;
  /// * [TreeNode.depth]: a depth shift comes from an ancestor whose parent
  ///   changed, and that ancestor is reported.
  ///
  /// The trees may have different type arguments; entries compare data with
  /// `==` regardless of type. [TreeOptions.order] is never read, so trees
  /// built with typed comparators are safe to pass as
  /// `DirectoryTree<Object?>`. Two empty trees give an empty diff.
  ///
  /// Runs in O(n + m) hash lookups and node comparisons for trees of n and m
  /// nodes; one node comparison costs at most O(path length).
  static TreeDiff compute(
    DirectoryTree<Object?> before,
    DirectoryTree<Object?> after,
  ) {
    final added = <NodeId>[];
    final changed = <NodeId>[];
    for (final node in after.nodes) {
      final old = before[node.id];
      if (old == null) {
        added.add(node.id);
      } else if (!identical(old, node) &&
          (old.kind != node.kind ||
              old.parent != node.parent ||
              old.label != node.label ||
              old.path != node.path ||
              old.entry != node.entry)) {
        changed.add(node.id);
      }
    }
    final removed = <NodeId>[
      for (final node in before.nodes)
        if (!after.contains(node.id)) node.id,
    ];
    return TreeDiff._(added, removed, changed);
  }

  /// Ids of nodes that are only in the new tree, in its pre-order
  /// ([DirectoryTree.nodes] order). The list is unmodifiable.
  final List<NodeId> added;

  /// Ids of nodes that are only in the old tree, in its pre-order. The list
  /// is unmodifiable.
  final List<NodeId> removed;

  /// Ids of nodes in both trees whose kind, path, label, entry, or parent
  /// differs, in the new tree's pre-order. The list is unmodifiable.
  final List<NodeId> changed;

  /// Whether no node was added, removed, or changed.
  ///
  /// True for equal trees, but also when only the sibling order differs
  /// (for example after changing [TreeOptions.order]).
  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;

  /// Whether [other] is a [TreeDiff] with equal [added], [removed], and
  /// [changed] lists (same ids in the same order).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeDiff &&
          _idsEqual(other.added, added) &&
          _idsEqual(other.removed, removed) &&
          _idsEqual(other.changed, changed);

  /// A hash of the three id lists, computed once and cached.
  @override
  late final int hashCode = Object.hash(
    Object.hashAll(added),
    Object.hashAll(removed),
    Object.hashAll(changed),
  );

  @override
  String toString() =>
      'TreeDiff(added: ${_format(added)}, removed: ${_format(removed)}, '
      'changed: ${_format(changed)})';
}

bool _idsEqual(List<NodeId> a, List<NodeId> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _format(List<NodeId> ids) => '[${ids.map((id) => id.value).join(', ')}]';
