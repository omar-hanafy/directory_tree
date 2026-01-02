import 'package:directory_tree/src/models/tree_data.dart';
import 'package:directory_tree/src/models/tree_node.dart';
import 'package:directory_tree/src/ops/path_utils.dart';
import 'package:directory_tree/src/ops/search_filter.dart';
import 'package:directory_tree/src/ops/sort_delegate.dart';
import 'package:directory_tree/src/ops/visible_node.dart';

/// Determines how the hierarchical tree is converted into a linear list for rendering.
///
/// Implement this to define the "view" of your tree (e.g., standard Explorer,
/// search results, or filtered views).
///
/// ### Behavior
/// *   **Expansion:** Implementations must respect [expandedIds] to decide which children to show.
/// *   **Filtering:** If [filterQuery] is present, prune the tree to show only matching nodes.
abstract class FlattenStrategy {
  /// Abstract constant constructor.
  const FlattenStrategy();

  /// Transforms the tree into a flat list of visible nodes.
  ///
  /// *   [data]: The tree structure to flatten.
  /// *   [expandedIds]: Set of folder IDs that are currently expanded.
  /// *   [filterQuery]: Optional search query to filter the tree.
  List<VisibleNode> flatten({
    required TreeData data,
    required Set<String> expandedIds,
    String? filterQuery,
  });
}

/// Traverses the tree depth-first, respecting expansion state.
///
/// Use this for standard file explorer behavior.
///
/// ### Behavior
/// *   **Order:** Visits folders then their children recursively.
/// *   **Filtering:** If a filter is active, it includes matching nodes AND their
///     ancestors (to preserve context), even if the ancestors don't match.
class DefaultFlattenStrategy extends FlattenStrategy {
  /// Creates a default DFS-based flattening strategy.
  const DefaultFlattenStrategy();

  @override
  List<VisibleNode> flatten({
    required TreeData data,
    required Set<String> expandedIds,
    String? filterQuery,
  }) {
    final nodes = data.nodes;
    final root = nodes[data.visibleRootId];
    if (root == null) return const <VisibleNode>[];

    final out = <VisibleNode>[];

    final pred = compileFilter(filterQuery);
    final hasFilter = filterQuery != null && filterQuery.trim().isNotEmpty;

    // Precompute "matches or has matching descendant" when filtering.
    final matchesCache = <String, bool>{};
    bool subtreeMatches(String id) {
      if (!hasFilter) return true;
      final cached = matchesCache[id];
      if (cached != null) return cached;
      final n = nodes[id]!;
      final self = pred(n.name, extensionLower(n.name));
      if (self) return matchesCache[id] = true;
      for (final cid in n.childIds) {
        if (subtreeMatches(cid)) {
          return matchesCache[id] = true;
        }
      }
      return matchesCache[id] = false;
    }

    void visit(String id, int depth, {required bool forceExpand}) {
      final n = nodes[id]!;
      // Skip nodes that don't match the filter (and have no matching children).
      if (!subtreeMatches(id)) return;

      final isFolder = n.type == NodeType.folder || n.type == NodeType.root;
      final hasChildren = n.childIds.isNotEmpty;

      out.add(
        VisibleNode(
          id: n.id,
          depth: depth,
          name: n.name,
          type: n.type,
          hasChildren: hasChildren,
          virtualPath: n.virtualPath,
          entryId: n.entryId,
          isVirtual: n.isVirtual,
          sourcePath: n.sourcePath,
          origin: n.origin,
        ),
      );

      // Decide whether to traverse children.
      final expanded = forceExpand || expandedIds.contains(n.id);
      if (isFolder && hasChildren && expanded) {
        for (final cid in n.childIds) {
          visit(cid, depth + 1, forceExpand: hasFilter && subtreeMatches(cid));
        }
      }
    }

    if (data.omitContainerRowAtRoot &&
        (root.type == NodeType.folder || root.type == NodeType.root)) {
      for (final cid in root.childIds) {
        visit(cid, 0, forceExpand: hasFilter && subtreeMatches(cid));
      }
    } else {
      visit(root.id, 0, forceExpand: hasFilter);
    }
    return out;
  }
}

/// Wraps the default traversal but sorts children using a [SortDelegate] before visiting them.
///
/// Use this when you need strict ordering (e.g., "Folders first", "Alphabetical").
class SortedFlattenStrategy extends DefaultFlattenStrategy {
  /// Creates a flattening strategy that sorts children using [delegate].
  const SortedFlattenStrategy(this.delegate);

  /// The delegate responsible for sorting children.
  final SortDelegate delegate;

  @override
  List<VisibleNode> flatten({
    required TreeData data,
    required Set<String> expandedIds,
    String? filterQuery,
  }) {
    final nodes = data.nodes;
    final root = nodes[data.visibleRootId];
    if (root == null) return const <VisibleNode>[];

    final out = <VisibleNode>[];
    final pred = compileFilter(filterQuery);
    final hasFilter = filterQuery != null && filterQuery.trim().isNotEmpty;

    final matchesCache = <String, bool>{};
    bool subtreeMatches(String id) {
      if (!hasFilter) return true;
      final cached = matchesCache[id];
      if (cached != null) return cached;
      final n = nodes[id]!;
      final self = pred(n.name, extensionLower(n.name));
      if (self) return matchesCache[id] = true;
      for (final cid in n.childIds) {
        if (subtreeMatches(cid)) return matchesCache[id] = true;
      }
      return matchesCache[id] = false;
    }

    void visit(String id, int depth, {required bool forceExpand}) {
      final n = nodes[id]!;
      if (!subtreeMatches(id)) return;

      final hasChildren = n.childIds.isNotEmpty;
      out.add(
        VisibleNode(
          id: n.id,
          depth: depth,
          name: n.name,
          type: n.type,
          hasChildren: hasChildren,
          virtualPath: n.virtualPath,
          entryId: n.entryId,
          isVirtual: n.isVirtual,
          sourcePath: n.sourcePath,
          origin: n.origin,
        ),
      );

      final expanded = forceExpand || expandedIds.contains(n.id);
      if ((n.type == NodeType.folder || n.type == NodeType.root) &&
          hasChildren &&
          expanded) {
        final ordered = delegate.sortChildIds(data, n.id);
        for (final cid in ordered) {
          visit(cid, depth + 1, forceExpand: hasFilter && subtreeMatches(cid));
        }
      }
    }

    if (data.omitContainerRowAtRoot &&
        (root.type == NodeType.folder || root.type == NodeType.root)) {
      final ordered = delegate.sortChildIds(data, root.id);
      for (final cid in ordered) {
        visit(cid, 0, forceExpand: hasFilter && subtreeMatches(cid));
      }
    } else {
      visit(root.id, 0, forceExpand: hasFilter);
    }
    return out;
  }
}
