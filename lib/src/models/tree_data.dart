import 'package:directory_tree/src/models/tree_node.dart';

/// Holds the complete state of the directory tree at a specific point in time.
///
/// [TreeData] is the "source of truth" for your UI. It contains the graph of
/// [TreeNode]s and the entry points for traversal.
///
/// ### Behavior
/// *   **Traversal:** Use [nodes] combined with [rootId] or [visibleRootId] to
///     walk the tree.
/// *   **Updates:** This class is immutable. To change the tree (e.g., expand a folder),
///     you typically create a new [TreeData] (or a sidecar state object) rather than mutating this one.
/// *   **Rendering:** Pass this to [FlattenStrategy.flatten] to produce a renderable list.
class TreeData {
  /// Creates a new [TreeData] instance.
  const TreeData({
    required this.nodes,
    required this.rootId,
    required this.visibleRootId,
    this.omitContainerRowAtRoot = false,
  });

  /// The flat storage of all nodes in the graph, indexed by their unique [TreeNode.id].
  ///
  /// This map represents the complete state of the tree. Traversal should start
  /// from [rootId] or [visibleRootId] and follow [TreeNode.childIds].
  ///
  /// **Invariant:** Every ID referenced in [TreeNode.childIds] must exist in this map.
  final Map<String, TreeNode> nodes;

  /// The fixed ID of the absolute technical root ('root').
  ///
  /// This node serves as the anchor for the entire graph but is rarely rendered directly.
  /// User-visible content usually starts at its child, [visibleRootId].
  final String rootId;

  /// The ID of the node where rendering should begin.
  ///
  /// This is typically the 'tree_root' folder, or a hoisted child folder if
  /// [TreeBuilder.autoPickVisibleRoot] optimized the view.
  ///
  /// Pass this to [FlattenStrategy.flatten] to generate the UI list.
  final String visibleRootId;

  /// Whether to hide the [visibleRootId] node and render its children at depth 0.
  ///
  /// Use this to create a "multi-root" feel where top-level folders appear
  /// side-by-side without a single parent container.
  final bool omitContainerRowAtRoot;
}
