// lib/src/ops/visible_node.dart
import 'package:directory_tree/src/models/tree_node.dart';

/// A lightweight view model representing a single row in the rendered tree list.
///
/// This object contains everything a UI needs to paint a row:
/// indentation [depth], [name], [icon] type, and [isExpanded] status
/// (implied by the presence of children in the following rows).
class VisibleNode {
  /// Creates a view model for a rendered tree row.
  const VisibleNode({
    required this.id,
    required this.depth,
    required this.name,
    required this.type,
    required this.hasChildren,
    required this.virtualPath,
    this.entryId,
    this.isVirtual = false,
    this.sourcePath,
    this.origin = SelectionOrigin.none,
  });

  /// The node's unique ID.
  final String id;

  /// The visual indentation level (0 for the top-level items).
  final int depth;

  /// The display name.
  final String name;

  /// The node type (folder, file, etc.), useful for choosing an icon.
  final NodeType type;

  /// Whether the node has children (used to show expansion arrow).
  final bool hasChildren;

  /// The full virtual path of the node.
  final String virtualPath;

  /// The entry ID, if this node is a file.
  final String? entryId;

  /// Whether this node is virtual.
  final bool isVirtual;

  /// The source path, if this node corresponds to a real file/folder.
  final String? sourcePath;

  /// How this node was added to the tree.
  final SelectionOrigin origin;
}
