part of 'directory_tree.dart';

/// One file or directory in a [DirectoryTree].
///
/// Nodes are immutable values created only by the tree builder. A node knows
/// its identity ([id]), canonical display [path], position ([parent],
/// [depth]), and the [entry] that produced it; navigation beyond the parent
/// goes through the owning tree ([DirectoryTree.childrenOf],
/// [DirectoryTree.ancestorsOf], and friends).
///
/// The class is sealed: every node is a [FileNode] or a [DirectoryNode], so a
/// `switch` over a node is exhaustive.
@immutable
sealed class TreeNode<T> {
  TreeNode._({
    required this.id,
    required this.path,
    required this.parent,
    required this.depth,
    required this.entry,
  });

  /// The stable identity of this node: [PathPolicy.idOf] of [path].
  final NodeId id;

  /// The canonical display path of this node.
  ///
  /// Spelling only varies under a case-insensitive [PathPolicy], where one
  /// node can stand for several spellings. A top-level node uses the parsed
  /// path of its entry, else its [TreeRoots.fixed] path, else (an inferred
  /// directory) the code-unit-smallest spelling of each segment among the
  /// entries inside it. Any other node's path is its parent's path plus its
  /// own name, spelled by its entry or, when inferred, by the
  /// code-unit-smallest spelling among the entries inside it. Only entries
  /// the tree keeps count: a file entry dropped as a conflict (see
  /// [TreeIssueKind.conflict]) spells nothing, so rebuilding from
  /// `DirectoryTree.entries` gives the same paths. So a subtree always
  /// displays consistently, and the spelling never depends on input order.
  final TreePath path;

  /// The last segment of [path], or a root name such as `/` or `C:`.
  String get name => path.name;

  /// The name to display for this node.
  ///
  /// Equals [name], except for top-level nodes whose names collide with
  /// other top-level nodes. Those get the shortest trailing part of their
  /// path that is unique among the top-level labels, such as `a/src` and
  /// `b/src`, falling back to the full canonical path string (for example
  /// `C:/src` and `D:/src`).
  // Top-level nodes are always directories, so only DirectoryNode stores a
  // label; a FileNode's label is its name, which saves a field per file.
  String get label;

  /// The id of the parent node, or `null` for top-level nodes.
  final NodeId? parent;

  /// The distance from the top-level ancestor: 0 for top-level nodes.
  final int depth;

  /// The entry that produced this node, or `null` for a directory that was
  /// inferred because entries lie inside it.
  final TreeEntry<T>? entry;

  /// The user data of [entry], or `null` when there is no entry or it has no
  /// data.
  T? get data => entry?.data;

  /// Whether an entry produced this node, as opposed to it being inferred.
  bool get isExplicit => entry != null;

  /// Whether this is a file or a directory.
  TreeNodeKind get kind;

  /// Whether this node is a [FileNode].
  bool get isFile => kind == TreeNodeKind.file;

  /// Whether this node is a [DirectoryNode].
  bool get isDirectory => kind == TreeNodeKind.directory;

  /// Whether this is a top-level node of its tree ([parent] is `null`).
  ///
  /// Not the same as [TreePath.isRoot]: a top-level node is usually a
  /// directory deep inside the file system, such as `/repo/lib`.
  bool get isRoot => parent == null;

  List<NodeId> get _childIds;

  /// Whether [other] is a node of the same kind with equal [id], [path],
  /// [label], [parent], [depth], [entry], and (for directories) children.
  ///
  /// The type argument is not compared. Runs in O(path length + number of
  /// children).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TreeNode<Object?>) return false;
    if (other.kind != kind ||
        other.id != id ||
        other.depth != depth ||
        other.parent != parent ||
        other.label != label ||
        other.path != path ||
        other.entry != entry) {
      return false;
    }
    final children = _childIds;
    final otherChildren = other._childIds;
    if (children.length != otherChildren.length) return false;
    for (var i = 0; i < children.length; i++) {
      if (children[i] != otherChildren[i]) return false;
    }
    return true;
  }

  /// A hash of the fields compared by [operator ==], computed once and
  /// cached.
  @override
  late final int hashCode = Object.hash(
    kind,
    id,
    path,
    label,
    parent,
    depth,
    entry,
    Object.hashAll(_childIds),
  );
}

/// A file in a [DirectoryTree]. Files never have children.
final class FileNode<T> extends TreeNode<T> {
  FileNode._({
    required super.id,
    required super.path,
    required super.parent,
    required super.depth,
    required super.entry,
  }) : super._();

  @override
  String get label => path.name;

  @override
  TreeNodeKind get kind => TreeNodeKind.file;

  @override
  List<NodeId> get _childIds => const <NodeId>[];

  @override
  String toString() => 'FileNode($path)';
}

/// A directory in a [DirectoryTree], explicit or inferred.
final class DirectoryNode<T> extends TreeNode<T> {
  DirectoryNode._({
    required super.id,
    required super.path,
    required this.label,
    required super.parent,
    required super.depth,
    required super.entry,
    required this.children,
  }) : super._();

  @override
  final String label;

  /// The ids of the direct children, in [TreeOptions.order].
  ///
  /// The list is unmodifiable. Use [DirectoryTree.childrenOf] to get the
  /// nodes.
  final List<NodeId> children;

  /// Whether [children] is not empty.
  bool get hasChildren => children.isNotEmpty;

  @override
  TreeNodeKind get kind => TreeNodeKind.directory;

  @override
  List<NodeId> get _childIds => children;

  @override
  String toString() => 'DirectoryNode($path, children: ${children.length})';
}
