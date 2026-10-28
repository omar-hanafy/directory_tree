import 'dart:collection';
import 'dart:typed_data';

import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/path/tree_path.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:directory_tree/src/tree/tree_entry.dart';
import 'package:directory_tree/src/tree/tree_issue.dart';
import 'package:directory_tree/src/tree/tree_options.dart';
import 'package:meta/meta.dart';

part 'tree_builder.dart';
part 'tree_node.dart';

/// An immutable, indexed directory tree built from a set of [TreeEntry]s.
///
/// The tree stores its [nodes] in pre-order (each node, then its children in
/// [TreeOptions.order]), with O(1) lookup by [NodeId] and O(1) subtree
/// ranges. That layout makes the common UI questions cheap: [indexOf] and
/// [subtreeSizeOf] give a node's slice of [nodes], [isAncestor] is two
/// lookups, and [descendantsOf] is a view, not a copy.
///
/// Build a tree with [DirectoryTree.build], [DirectoryTree.fromPaths], or a
/// [DirectoryTreeBuilder]. Building is deterministic: the same entries
/// (unique paths) in any order produce an equal tree with an identical
/// [nodes] order, and node ids are stable across rebuilds. Bad input never
/// throws; it is skipped and reported in [issues].
///
/// ```dart
/// final tree = DirectoryTree.fromPaths([
///   '/repo/lib/main.dart',
///   '/repo/lib/src/tree.dart',
///   '/repo/README.md',
/// ]);
/// print(tree.rootNodes.single.name); // repo
/// final lib = tree.nodeAt('/repo/lib')!;
/// print(tree.childrenOf(lib.id).map((node) => node.name)); // (src, main.dart)
/// ```
///
/// To change a tree, derive a new one with [rebuild] or [toBuilder]; the
/// original never changes.
///
/// Lookups never throw for unknown ids: they return `null`, `-1`, `0`,
/// `false`, or an empty result.
@immutable
final class DirectoryTree<T> {
  DirectoryTree._({
    required this.options,
    required List<TreeNode<T>> nodes,
    required Map<NodeId, int> indexById,
    required Int32List parentIndices,
    required Int32List subtreeSizes,
    required List<int> rootIndices,
    required List<TreeEntry<T>> entries,
    required List<TreeIssue<T>> issues,
    required this.fileCount,
  }) : _nodes = nodes,
       _indexById = indexById,
       _parentIndices = parentIndices,
       _subtreeSizes = subtreeSizes,
       _rootIndices = rootIndices,
       _entries = entries,
       _issues = issues,
       roots = List<NodeId>.unmodifiable(
         rootIndices.map((index) => nodes[index].id),
       ),
       rootNodes = List<TreeNode<T>>.unmodifiable(
         rootIndices.map((index) => nodes[index]),
       );

  /// Builds a tree from [entries] using [options].
  ///
  /// Each entry path is parsed by [TreeOptions.paths]. Entries that map to
  /// the same [NodeId] merge: the later entry wins and keeps the position of
  /// the first one. Directories between the top-level nodes and the entries
  /// are created automatically. Invalid paths, conflicts, and entries outside
  /// fixed roots are skipped and listed in [issues].
  ///
  /// Runs in O(L + n log n) for L total path length and n nodes, plus the
  /// size of the node paths and ids it creates. To build incrementally, use
  /// a [DirectoryTreeBuilder].
  factory DirectoryTree.build(
    Iterable<TreeEntry<T>> entries, {
    TreeOptions options = const TreeOptions(),
  }) => DirectoryTreeBuilder<T>(options: options, entries: entries).build();

  /// Creates a tree without entries.
  ///
  /// With [TreeRoots.fixed] the fixed roots still appear, since fixed roots
  /// exist even when empty; otherwise the tree has no nodes.
  factory DirectoryTree.empty({TreeOptions options = const TreeOptions()}) =>
      DirectoryTreeBuilder<T>(options: options).build();

  /// Builds a tree from raw path strings, without entry data.
  ///
  /// Each path becomes a file entry, except a path that ends with a
  /// separator (`/`, or `\` when [PathPolicy.backslashIsSeparator] is set),
  /// which becomes a directory entry. Use it for quick trees from lists such
  /// as `git ls-files` output.
  static DirectoryTree<Never> fromPaths(
    Iterable<String> paths, {
    TreeOptions options = const TreeOptions(),
  }) {
    final backslash = options.paths.backslashIsSeparator;
    return DirectoryTree<Never>.build([
      for (final path in paths)
        if (path.isNotEmpty &&
            isPathSeparator(
              path.codeUnitAt(path.length - 1),
              backslashIsSeparator: backslash,
            ))
          TreeEntry<Never>.directory(path)
        else
          TreeEntry<Never>.file(path),
    ], options: options);
  }

  /// The options this tree was built with.
  final TreeOptions options;

  /// The ids of the top-level nodes, in [TreeOptions.order].
  ///
  /// Which directories are top level depends on [TreeOptions.roots]. The
  /// list is unmodifiable.
  final List<NodeId> roots;

  /// The top-level nodes, in the same order as [roots].
  final List<TreeNode<T>> rootNodes;

  final List<TreeNode<T>> _nodes;
  final Map<NodeId, int> _indexById;
  final Int32List _parentIndices;
  final Int32List _subtreeSizes;
  final List<int> _rootIndices;
  final List<TreeEntry<T>> _entries;
  final List<TreeIssue<T>> _issues;

  /// Every node in pre-order: each top-level node in [roots] order, followed
  /// by its descendants, each directory's children in [TreeOptions.order].
  ///
  /// The subtree of the node at index `i` occupies indexes `i` to
  /// `i + subtreeSizeOf(id) - 1`. The list is unmodifiable.
  List<TreeNode<T>> get nodes => _nodes;

  /// The number of nodes.
  int get length => _nodes.length;

  /// Whether the tree has no nodes.
  bool get isEmpty => _nodes.isEmpty;

  /// Whether the tree has at least one node.
  bool get isNotEmpty => _nodes.isNotEmpty;

  /// The number of [FileNode]s.
  final int fileCount;

  /// The number of [DirectoryNode]s, explicit or inferred.
  int get directoryCount => _nodes.length - fileCount;

  /// The file nodes in pre-order. Lazy; each iteration walks [nodes].
  Iterable<FileNode<T>> get files => _nodes.whereType<FileNode<T>>();

  /// The directory nodes in pre-order. Lazy; each iteration walks [nodes].
  Iterable<DirectoryNode<T>> get directories =>
      _nodes.whereType<DirectoryNode<T>>();

  /// The entries that produced nodes, in first-insertion order.
  ///
  /// Entries merged by id appear once, with the last value at the first
  /// position. Entries that were skipped (see [issues]) are not included.
  /// The list is unmodifiable.
  List<TreeEntry<T>> get entries => _entries;

  /// The problems found while building, in input order.
  ///
  /// Issues about [TreeRoots.fixed] paths come first, then issues about
  /// entries in entry order. Empty when every input was used. The list is
  /// unmodifiable.
  List<TreeIssue<T>> get issues => _issues;

  /// The node with [id], or `null` when the tree has no such node. O(1).
  TreeNode<T>? operator [](NodeId id) {
    final index = _indexById[id];
    return index == null ? null : _nodes[index];
  }

  /// Whether the tree has a node with [id]. O(1).
  bool contains(NodeId id) => _indexById.containsKey(id);

  /// The id that the raw [path] has under [TreeOptions.paths], whether or
  /// not the tree contains it.
  ///
  /// Returns `null` when [path] cannot be parsed. Use it to turn user input
  /// or persisted paths into ids; see [nodeAt] to look up the node directly.
  NodeId? idOf(String path) {
    final policy = options.paths;
    final parsed = policy.tryParse(path);
    return parsed == null ? null : policy.idOf(parsed);
  }

  /// The node at the raw [path], or `null` when the path is invalid or not
  /// in the tree.
  ///
  /// The path is parsed with [TreeOptions.paths], so with a case-insensitive
  /// policy `nodeAt('/REPO/lib')` finds `/repo/lib`.
  TreeNode<T>? nodeAt(String path) {
    final id = idOf(path);
    return id == null ? null : this[id];
  }

  /// The index of the node with [id] in [nodes], or -1 when absent. O(1).
  int indexOf(NodeId id) => _indexById[id] ?? -1;

  /// The number of nodes in the subtree of [id], including the node itself;
  /// 0 when absent. O(1).
  ///
  /// The subtree is the slice of [nodes] starting at [indexOf], so a file's
  /// subtree size is 1.
  int subtreeSizeOf(NodeId id) {
    final index = _indexById[id];
    return index == null ? 0 : _subtreeSizes[index];
  }

  /// The children of [id] in [TreeOptions.order]; empty for files and
  /// unknown ids.
  ///
  /// Runs in O(number of children). The list is unmodifiable.
  List<TreeNode<T>> childrenOf(NodeId id) {
    final index = _indexById[id];
    if (index == null) return const [];
    final end = index + _subtreeSizes[index];
    final children = <TreeNode<T>>[];
    for (var child = index + 1; child < end; child += _subtreeSizes[child]) {
      children.add(_nodes[child]);
    }
    return UnmodifiableListView<TreeNode<T>>(children);
  }

  /// The parent of [id], or `null` for top-level nodes and unknown ids.
  /// O(1).
  TreeNode<T>? parentOf(NodeId id) {
    final index = _indexById[id];
    if (index == null) return null;
    final parent = _parentIndices[index];
    return parent < 0 ? null : _nodes[parent];
  }

  /// The top-level node whose subtree contains [id] (the node itself when it
  /// is top level), or `null` for unknown ids. O(log number of roots).
  TreeNode<T>? rootOf(NodeId id) {
    final index = _indexById[id];
    if (index == null) return null;
    // Roots appear in increasing pre-order index; find the last root at or
    // before [index].
    var low = 0;
    var high = _rootIndices.length - 1;
    while (low < high) {
      final middle = low + (high - low + 1) ~/ 2;
      if (_rootIndices[middle] <= index) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return _nodes[_rootIndices[low]];
  }

  /// The ancestors of [id], nearest first, excluding the node itself.
  ///
  /// Empty for top-level nodes and unknown ids. Lazy; each iteration walks
  /// up in O(depth).
  Iterable<TreeNode<T>> ancestorsOf(NodeId id) sync* {
    final index = _indexById[id];
    if (index == null) return;
    for (var parent = _parentIndices[index]; parent >= 0;) {
      yield _nodes[parent];
      parent = _parentIndices[parent];
    }
  }

  /// The descendants of [id] in pre-order, excluding the node itself.
  ///
  /// This is a view of the slice of [nodes] after [indexOf], created in
  /// O(1). Empty for files and unknown ids.
  Iterable<TreeNode<T>> descendantsOf(NodeId id) {
    final index = _indexById[id];
    if (index == null) return const [];
    return _nodes.getRange(index + 1, index + _subtreeSizes[index]);
  }

  /// Whether [ancestor] is a strict ancestor of [descendant]. O(1).
  ///
  /// False when either id is unknown and when both ids are equal.
  bool isAncestor(NodeId ancestor, NodeId descendant) {
    final outer = _indexById[ancestor];
    final inner = _indexById[descendant];
    if (outer == null || inner == null) return false;
    return outer < inner && inner < outer + _subtreeSizes[outer];
  }

  /// Returns a builder seeded with this tree's [options] and [entries].
  ///
  /// Skipped inputs (see [issues]) are not carried over. Changing the
  /// builder does not affect this tree.
  @useResult
  DirectoryTreeBuilder<T> toBuilder() =>
      DirectoryTreeBuilder<T>(options: options, entries: _entries);

  /// Returns a new tree with the changes that [update] makes to a builder
  /// seeded from this tree.
  ///
  /// ```dart
  /// final next = tree.rebuild((builder) => builder
  ///   ..addFile('/repo/lib/new.dart')
  ///   ..remove('/repo/old'));
  /// ```
  ///
  /// Unchanged paths keep their ids, so expansion and selection state keyed
  /// by [NodeId] carries over. Runs a full build; see [DirectoryTree.build].
  @useResult
  DirectoryTree<T> rebuild(
    void Function(DirectoryTreeBuilder<T> builder) update,
  ) {
    final builder = toBuilder();
    update(builder);
    return builder.build();
  }

  /// Whether [other] is a [DirectoryTree] with equal [options] and equal
  /// [nodes] in the same order.
  ///
  /// Runs in O(n) (after an O(1) check of the cached [hashCode]); [issues]
  /// are not compared.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DirectoryTree<Object?>) return false;
    final otherNodes = other._nodes;
    if (otherNodes.length != _nodes.length ||
        other.hashCode != hashCode ||
        other.options != options) {
      return false;
    }
    for (var i = 0; i < _nodes.length; i++) {
      if (otherNodes[i] != _nodes[i]) return false;
    }
    return true;
  }

  /// A hash of [options] and [nodes], computed once in O(n) and cached.
  @override
  late final int hashCode = Object.hash(options, Object.hashAll(_nodes));

  /// A one-line summary such as
  /// `DirectoryTree(roots: 1, nodes: 5, files: 3, issues: 0)`.
  @override
  String toString() =>
      'DirectoryTree(roots: ${roots.length}, nodes: ${_nodes.length}, '
      'files: $fileCount, issues: ${_issues.length})';
}
