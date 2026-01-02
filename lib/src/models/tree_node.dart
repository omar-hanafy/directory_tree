import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Describes the type of a node in the tree graph.
enum NodeType {
  /// The hidden top-level container for the entire tree structure.
  root,

  /// A container node that can hold other folders or files.
  folder,

  /// A leaf node representing a specific [TreeEntry].
  file,
}

/// Indicates how a folder came to exist in the tree.
///
/// This is crucial for "TRD" (Tree Representation Definition) compliance,
/// allowing the UI to distinguish between folders the user explicitly added
/// vs. folders created automatically to hold files.
enum SelectionOrigin {
  /// Not a folder or unknown origin.
  none,

  /// Created automatically because it is an ancestor of a file.
  inferred,

  /// Explicitly added by the user (e.g., "Open Folder").
  direct,
}

/// A vertex in the [TreeData] graph representing a file or folder.
///
/// [TreeNode] contains the structural connections (parent/children) and visual
/// state needed to render the tree.
///
/// ### Behavior
/// *   **Navigation:** Use [childIds] to traverse down and [parentId] to traverse up.
/// *   **File IO:** Use [sourcePath] for physical file operations.
/// *   **UI Logic:** Use [virtualPath] for display logic and finding nodes, as it
///     is normalized and deterministic.
class TreeNode extends Equatable {
  /// Creates a new [TreeNode].
  TreeNode({
    required this.name,
    required this.type,
    required this.parentId,
    required this.virtualPath,
    String? id,
    this.sourcePath,
    this.entryId,
    this.isVirtual = false,
    this.isExpanded = false,
    this.isSelected = false,
    List<String>? childIds,
    this.origin = SelectionOrigin.none,
  }) : id = id ?? const Uuid().v4(),
       childIds = childIds ?? const [];

  /// Unique identifier for this node in the graph.
  final String id;

  /// Display name of the node.
  final String name;

  /// The type of node (root, folder, or file).
  final NodeType type;

  /// The ID of the parent node.
  final String parentId;

  /// The IDs of immediate children, defining the structure of the tree.
  ///
  /// These IDs must correspond to keys in [TreeData.nodes].
  /// The order here determines the default visual order unless a [SortDelegate]
  /// reorders them during flattening.
  final List<String> childIds;

  /// Original path if this node corresponds to a real file/folder.
  final String? sourcePath;

  /// The normalized, deterministic path in the virtual file system.
  ///
  /// This path uses forward slashes `/` regardless of the OS and is used for
  /// path-based lookups and establishing uniqueness.
  ///
  /// Example: `/root/tree/my_project/src`
  final String virtualPath;

  /// Links to [TreeEntry.id] for file nodes.
  final String? entryId;

  /// Whether this node was created virtually (not on disk).
  final bool isVirtual;

  /// Whether the folder is currently expanded in the UI.
  final bool isExpanded;

  /// Whether the node is selected in the UI.
  final bool isSelected;

  /// How this node was added to the tree (direct selection vs inferred).
  final SelectionOrigin origin;

  /// Creates a copy of this node with the given fields replaced.
  TreeNode copyWith({
    String? name,
    bool? isExpanded,
    bool? isSelected,
    List<String>? childIds,
    String? sourcePath,
    SelectionOrigin? origin,
  }) {
    return TreeNode(
      id: id,
      name: name ?? this.name,
      type: type,
      parentId: parentId,
      virtualPath: virtualPath,
      sourcePath: sourcePath ?? this.sourcePath,
      entryId: entryId,
      isVirtual: isVirtual,
      isExpanded: isExpanded ?? this.isExpanded,
      isSelected: isSelected ?? this.isSelected,
      childIds: childIds ?? this.childIds,
      origin: origin ?? this.origin,
    );
  }

  @override
  List<Object?> get props => [id];
}
