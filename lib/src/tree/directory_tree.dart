import 'dart:collection';
import 'dart:typed_data';

import 'package:directory_tree/src/filter/tree_filter.dart';
import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/path/tree_path.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:directory_tree/src/tree/tree_entry.dart';
import 'package:directory_tree/src/tree/tree_issue.dart';
import 'package:directory_tree/src/tree/tree_options.dart';
import 'package:directory_tree/src/view/expansion_state.dart';
import 'package:directory_tree/src/view/tree_renderer.dart';
import 'package:directory_tree/src/view/tree_rows.dart';
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

  /// Returns the visible rows of a tree view of this tree, in display
  /// order.
  ///
  /// This is the bridge to a UI: [TreeRows] is a [List] of [TreeRow]s that a
  /// virtualized list view shows directly, each with a stable key
  /// ([TreeRow.id]), indentation, expand arrow, connector lines, and label.
  /// Keep the result and update it with [TreeRows.toggleNode],
  /// [TreeRows.expandNode], and [TreeRows.collapseNode], which only build
  /// the rows that change, instead of flattening again.
  ///
  /// The rows are this tree's pre-order restricted to visible nodes: a
  /// top-level node is visible (unless [showRoots] is false), and a child is
  /// visible when its parent's row is visible and expanded.
  ///
  /// * [expansion] decides which directories show their children. Defaults
  ///   to every directory expanded.
  /// * [filter] keeps only the nodes that match it or have a matching
  ///   descendant; [TreeRow.isMatch] tells the two apart. A `null` filter,
  ///   or one that reports [TreeFilter.matchesAll] (such as an empty search
  ///   query), shows every node. The filter is called exactly once per node
  ///   and never again by updates of the returned rows.
  /// * [expandMatches] (default true) adds every ancestor of every match to
  ///   [expansion] before flattening, so all matches are visible. The rows'
  ///   [TreeRows.expansion] is that effective state, so the user can still
  ///   collapse revealed directories. With false, [expansion] is used as
  ///   given and matches inside collapsed directories stay hidden. Without a
  ///   filter it has no effect.
  /// * [compactFolders] shows a directory whose only child is a directory on
  ///   one row with that child, repeatedly (`lib/src/utils`), as VS Code
  ///   does. Compaction follows the tree structure, not the filter; the row
  ///   expands and collapses as its deepest directory ([TreeRow.node]).
  /// * [showRoots] (default true) makes the top-level nodes rows. Set it to
  ///   false for an explorer of one folder whose name is a title rather than
  ///   a row (typically a tree with a single [TreeRoots.fixed] root). Then:
  ///   * the top-level nodes produce no rows and count as expanded whatever
  ///     [expansion] says. Their visible children are the depth-0 rows, in
  ///     root order and then child order, and every row is one level
  ///     shallower than with the roots shown.
  ///   * all depth-0 rows are siblings for [TreeRow.isLast] and
  ///     [TreeRow.guides], as if the roots did not exist: only the very last
  ///     depth-0 row is last, even across roots.
  ///   * a top-level id has no row ([TreeRows.indexOfNode] is -1 and
  ///     [TreeRows.rowOf] is `null`), [TreeRows.parentIndexOf] of a depth-0
  ///     row is `null`, and [TreeRows.expandNode], [TreeRows.collapseNode],
  ///     and [TreeRows.toggleNode] ignore top-level ids.
  ///   * [compactFolders] never merges a root with its child; chains start
  ///     below the roots.
  ///   * with a [filter], a root never produces a row, even when it
  ///     matches; matches below it show as usual, and [expandMatches] still
  ///     reveals them (adding their ancestors, roots included, to the
  ///     state).
  ///
  /// ```dart
  /// final tree = DirectoryTree.fromPaths([
  ///   '/repo/lib/main.dart',
  ///   '/repo/lib/src/tree.dart',
  ///   '/repo/README.md',
  /// ]);
  /// var rows = tree.flatten(expansion: const ExpansionState.collapsed());
  /// print(rows.map((row) => row.label)); // (repo)
  /// rows = rows.toggleNode(rows.first.id);
  /// print(rows.map((row) => row.label)); // (repo, lib, README.md)
  ///
  /// final contents = tree.flatten(
  ///   expansion: const ExpansionState.collapsed(),
  ///   showRoots: false,
  /// );
  /// print(contents.map((row) => row.label)); // (lib, README.md)
  /// ```
  ///
  /// An empty tree, or a filter that matches nothing, gives empty rows.
  /// Without a filter this runs in O(rows + roots): each collapsed
  /// directory's subtree is skipped in O(1). With a filter it runs in O(n)
  /// for n nodes and keeps about 9 bytes per node of match results, which
  /// the returned rows share with every update. Uses no recursion, so depth
  /// is unlimited.
  @useResult
  TreeRows<T> flatten({
    ExpansionState expansion = const ExpansionState.expanded(),
    TreeFilter? filter,
    bool expandMatches = true,
    bool compactFolders = false,
    bool showRoots = true,
  }) => flattenTree<T>(
    this,
    expansion: expansion,
    filter: filter,
    expandMatches: expandMatches,
    compactFolders: compactFolders,
    showRoots: showRoots,
  );

  /// Renders this tree as text, one line per visible row, like the `tree`
  /// command.
  ///
  /// ```dart
  /// final tree = DirectoryTree.fromPaths([
  ///   '/repo/lib/main.dart',
  ///   '/repo/lib/src/tree.dart',
  ///   '/repo/README.md',
  /// ]);
  /// print(tree.render());
  /// // repo/
  /// // ├── lib/
  /// // │   ├── src/
  /// // │   │   └── tree.dart
  /// // │   └── main.dart
  /// // └── README.md
  /// ```
  ///
  /// The lines are the rows of `flatten(expansion: expansion, filter:
  /// filter, compactFolders: compactFolders, showRoots: showRoots)`, so a
  /// filter reveals its matches (`expandMatches` is true) and collapsed
  /// directories show without their children. Each depth-0 row starts at
  /// the left margin. A row at depth `d >= 1` is prefixed, for each ancestor
  /// level `1` to `d - 1`, with [TreeStyle.pipe] when [TreeRow.guides] is
  /// true at that level and [TreeStyle.gap] otherwise, then with
  /// [TreeStyle.lastBranch] when [TreeRow.isLast] and [TreeStyle.branch]
  /// otherwise.
  ///
  /// * [style] picks the connectors; defaults to [TreeStyle.unicode].
  /// * [showRoots] false leaves out the top-level nodes, as in [flatten]:
  ///   their children start at the left margin, and everything below moves
  ///   one level left with its connectors.
  /// * [maxDepth] omits rows deeper than it: 0 prints only the depth-0 rows
  ///   (the top-level nodes, or their children when [showRoots] is false),
  ///   `null` (the default) has no limit, and a negative value prints
  ///   nothing. The remaining rows keep their connectors.
  /// * [label] returns the text of each row; by default [TreeRow.label],
  ///   followed by `/` for directories unless the label already ends with
  ///   `/` (as the POSIX root `/` does).
  ///
  /// Lines are joined with `\n`, without a trailing newline; an empty tree
  /// renders as the empty string. Runs in O(n) with a filter (one filter
  /// call per node), otherwise in O(rows printed + roots), plus the length
  /// of the output. Uses no recursion, so depth is unlimited.
  @useResult
  String render({
    TreeStyle style = TreeStyle.unicode,
    ExpansionState expansion = const ExpansionState.expanded(),
    TreeFilter? filter,
    bool compactFolders = false,
    bool showRoots = true,
    int? maxDepth,
    String Function(TreeRow<T> row)? label,
  }) => renderTree<T>(
    this,
    style: style,
    expansion: expansion,
    filter: filter,
    compactFolders: compactFolders,
    showRoots: showRoots,
    maxDepth: maxDepth,
    label: label,
  );

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
