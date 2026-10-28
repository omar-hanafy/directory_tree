import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:directory_tree/src/filter/tree_filter.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:directory_tree/src/view/expansion_state.dart';
// Imported only so documentation references to TreeStyle resolve.
import 'package:directory_tree/src/view/tree_renderer.dart';
import 'package:meta/meta.dart';

/// One visible line of a tree view: a node, or a chain of compacted
/// directories, with everything needed to draw it.
///
/// Rows come from [DirectoryTree.flatten] as the elements of a [TreeRows]
/// list; there is no public constructor. A row carries the indentation
/// ([depth]), the expand arrow ([isExpanded], [hasChildren]), the connector
/// lines ([isLast], [guides]), the text ([label]), and whether the filter
/// matched it ([isMatch]).
///
/// ```dart
/// final rows = tree.flatten();
/// for (final row in rows) {
///   final arrow = row.hasChildren ? (row.isExpanded ? 'v ' : '> ') : '  ';
///   print('${'  ' * row.depth}$arrow${row.label}');
/// }
/// ```
///
/// Rows are immutable values. [TreeRows.expandNode], [TreeRows.collapseNode],
/// and [TreeRows.toggleNode] reuse the row objects they do not change, so
/// `identical` tells a list view which rows to rebuild.
@immutable
final class TreeRow<T> {
  TreeRow._({
    required this.node,
    required this.depth,
    required this.isExpanded,
    required this.hasChildren,
    required this.isLast,
    required this.isMatch,
    required TreeRow<T>? parent,
    required int start,
    required List<TreeNode<T>>? chain,
    required String? label,
  }) : _parent = parent,
       _start = start,
       _chain = chain,
       _label = label;

  /// The node this row stands for: the deepest node of [chain].
  ///
  /// For a compacted row (see [TreeRows.compactFolders]) the expansion
  /// state, [hasChildren], and the child rows all belong to this node; the
  /// other chain members only contribute to [label].
  final TreeNode<T> node;

  /// The id of [node]; a stable key for list views.
  ///
  /// Ids survive [DirectoryTree.rebuild], so a row keeps its key when the
  /// tree changes around it.
  NodeId get id => node.id;

  /// The indentation level: 0 for top-level rows, otherwise the depth of the
  /// parent row plus one.
  ///
  /// Equals [TreeNode.depth] of the first node of [chain], minus the number
  /// of ancestor directories that compacted rows absorbed.
  final int depth;

  /// Whether [node] is a directory that is expanded in
  /// [TreeRows.expansion]; always false for files.
  ///
  /// An expanded row shows its child rows right after it. A directory can be
  /// expanded and still show none when [hasChildren] is false.
  final bool isExpanded;

  /// Whether expanding this row would show at least one child row.
  ///
  /// False for files and empty directories. Under a filter, also false for a
  /// directory none of whose children match or contain a match. Use it to
  /// decide whether to draw an expand arrow.
  final bool hasChildren;

  /// Whether no later sibling row follows this one under the same parent
  /// row (or among the top-level rows).
  ///
  /// Siblings hidden by the filter do not count. Text trees draw `└── `
  /// instead of `├── ` for the last row; see [TreeStyle].
  final bool isLast;

  /// Whether a node of [chain] matched the filter itself, as opposed to
  /// being shown only because a descendant matched.
  ///
  /// True for every row when the rows have no filter. Use it to highlight
  /// matches and dim the ancestors that lead to them.
  final bool isMatch;

  /// For each ancestor level, whether a vertical guide line continues
  /// through that column.
  ///
  /// `guides.length == depth`, and `guides[i]` is true when this row's
  /// ancestor row at depth `i` has a later visible sibling (its [isLast] is
  /// false), so the line from that ancestor to its next sibling passes this
  /// row. Text trees draw a pipe for true and a gap for false; see
  /// [DirectoryTree.render].
  ///
  /// Computed from the ancestor rows on first access, in O(depth), then
  /// cached. The list is unmodifiable.
  late final List<bool> guides = _buildGuides();

  /// The nodes this row stands for, outermost first; ends with [node].
  ///
  /// A single node unless [TreeRows.compactFolders] merged a run of
  /// directories that each have exactly one child directory, such as
  /// `lib`, `src`, `utils` shown as one row `lib/src/utils`. The list is
  /// unmodifiable.
  late final List<TreeNode<T>> chain =
      _chain ?? List<TreeNode<T>>.unmodifiable(<TreeNode<T>>[node]);

  /// The text to display: the [TreeNode.label]s of [chain] joined with `/`.
  ///
  /// For an uncompacted row this is `node.label`, which is the node's name
  /// except for top-level nodes whose names collide (`a/src`, `b/src`). A
  /// `/` is not doubled after a label that already ends with one, so a
  /// compacted POSIX root reads `/usr/lib`, not `//usr/lib`.
  String get label => _label ?? node.label;

  // The parent row, for [guides]; null for top-level rows. It is always the
  // row object present in the same TreeRows: updates replace a row only
  // together with its whole block of descendant rows.
  final TreeRow<T>? _parent;

  // Pre-order index (in DirectoryTree.nodes) of the first node of [chain].
  // Chains are contiguous in pre-order, so the row covers the indexes
  // _start.._end, and rows are sorted by _start.
  final int _start;

  // The chain when it has more than one node; null otherwise.
  final List<TreeNode<T>>? _chain;

  // The joined label of a compacted chain; null otherwise.
  final String? _label;

  int get _end => _start + (_chain?.length ?? 1) - 1;

  /// Whether [other] is a [TreeRow] with an equal [chain] (so an equal
  /// [node] and [label]), [depth], [isExpanded], [hasChildren], [isLast],
  /// [isMatch], and [guides].
  ///
  /// Rows of different [TreeRows] compare by value, so a row produced by an
  /// incremental update equals the row a full [DirectoryTree.flatten]
  /// produces. Runs in O(depth + chain length) plus the node comparisons.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TreeRow<Object?> ||
        other.depth != depth ||
        other.isExpanded != isExpanded ||
        other.hasChildren != hasChildren ||
        other.isLast != isLast ||
        other.isMatch != isMatch ||
        (other._chain?.length ?? 1) != (_chain?.length ?? 1) ||
        other.node != node) {
      return false;
    }
    final chain = this.chain;
    final otherChain = other.chain;
    for (var i = 0; i < chain.length - 1; i++) {
      if (otherChain[i] != chain[i]) return false;
    }
    final guides = this.guides;
    final otherGuides = other.guides;
    for (var i = 0; i < guides.length; i++) {
      if (otherGuides[i] != guides[i]) return false;
    }
    return true;
  }

  /// A hash of [node], [depth], the flags, and the chain length.
  ///
  /// Leaves out [guides] and the other chain nodes (equal rows still hash
  /// equally), so it never computes the guides and costs O(1) once the
  /// node's own cached hash exists.
  @override
  int get hashCode => Object.hash(
    node,
    depth,
    isExpanded,
    hasChildren,
    isLast,
    isMatch,
    _chain?.length ?? 1,
  );

  /// A description listing the label, the depth, the flags that are true,
  /// and the [guides], such as
  /// `TreeRow(repo, depth: 0, expanded, children, last, match, guides: [])`.
  @override
  String toString() {
    final flags = [
      if (isExpanded) 'expanded',
      if (hasChildren) 'children',
      if (isLast) 'last',
      if (isMatch) 'match',
    ];
    final flagText = flags.isEmpty ? '' : ', ${flags.join(', ')}';
    return 'TreeRow($label, depth: $depth$flagText, guides: $guides)';
  }

  /// A copy with [isExpanded] replaced, at the same position.
  TreeRow<T> _withExpanded({required bool expanded}) => TreeRow<T>._(
    node: node,
    depth: depth,
    isExpanded: expanded,
    hasChildren: hasChildren,
    isLast: isLast,
    isMatch: isMatch,
    parent: _parent,
    start: _start,
    chain: _chain,
    label: _label,
  );

  List<bool> _buildGuides() {
    if (depth == 0) return const <bool>[];
    final guides = List<bool>.filled(depth, false);
    var ancestor = _parent;
    for (var level = depth - 1; level >= 0; level--) {
      guides[level] = !ancestor!.isLast;
      ancestor = ancestor._parent;
    }
    return List<bool>.unmodifiable(guides);
  }
}

/// The visible rows of a [DirectoryTree] view, in display order, with
/// lookup, keyboard navigation, and incremental expand and collapse.
///
/// Create rows with [DirectoryTree.flatten]. The list holds one [TreeRow]
/// per visible node (or per compacted chain of directories): the tree's
/// pre-order restricted to nodes whose parent row is expanded (top-level
/// nodes are always candidates). It is an
/// unmodifiable [List], so it plugs straight into a virtualized list view:
/// `itemCount: rows.length`, `itemBuilder: (_, i) => draw(rows[i])`. Every
/// mutating [List] method throws an [UnsupportedError], even when the call
/// would change nothing.
///
/// ```dart
/// var rows = tree.flatten(expansion: const ExpansionState.collapsed());
/// rows = rows.toggleNode(rows.first.id); // the user clicked the first row
/// final row = rows.rowOf(tree.idOf('/repo/lib')!);
/// ```
///
/// ## Filters and compact folders
///
/// With a [filter], a node is visible only when it or a descendant matches;
/// [TreeRow.isMatch] tells which. Rows created with `expandMatches: true`
/// (the [DirectoryTree.flatten] default) have every ancestor of a match
/// added to [expansion], so the matches are visible and can still be
/// collapsed one by one. With [compactFolders], a directory that has exactly
/// one child, which is itself a directory, shares a row with that child, as
/// in the compact folders of VS Code. Compaction depends only on the tree's
/// structure, not on the filter.
///
/// ## Incremental updates
///
/// [expandNode], [collapseNode], and [toggleNode] return new rows that equal
/// what
/// [DirectoryTree.flatten] would return for the updated [expansion] with the
/// same [filter] and [compactFolders] and `expandMatches: false`, but they
/// only build the rows that change: expanding a row inserts its newly
/// visible descendants right after it, collapsing removes them, and every
/// other row is the identical [TreeRow] object as before. The filter is
/// never called again; match results computed by the original flatten are
/// shared by every [TreeRows] derived from it.
///
/// ## Keyboard navigation
///
/// [indexOfNode] finds the row of a node (also when the node is hidden
/// inside a compacted row), [parentIndexOf] moves to the parent row (left
/// arrow), and [firstChildIndexOf] to the first child row (right arrow).
/// Up and down are `index - 1` and `index + 1`.
final class TreeRows<T> extends ListBase<TreeRow<T>> {
  TreeRows._(this._source, this.expansion, this._rows);

  final _RowSource<T> _source;
  final List<TreeRow<T>> _rows;

  /// The tree these rows show.
  DirectoryTree<T> get tree => _source.tree;

  /// The expansion state the rows reflect.
  ///
  /// When the rows were created with a filter and `expandMatches: true`,
  /// this is the given state with every ancestor of a match expanded, not
  /// the state passed to [DirectoryTree.flatten]. Store this value (for
  /// example with [ExpansionState.toJson]) to restore the view as the user
  /// left it.
  final ExpansionState expansion;

  /// The filter that decides which nodes are visible, or `null` when every
  /// node is a candidate.
  ///
  /// `null` both when no filter was given and when the given filter reports
  /// [TreeFilter.matchesAll] (such as an empty search query).
  TreeFilter? get filter => _source.filter;

  /// Whether chains of single-child directories share one row.
  ///
  /// See [TreeRow.chain].
  bool get compactFolders => _source.compactFolders;

  /// The number of visible rows.
  ///
  /// Setting it throws an [UnsupportedError]: the list is unmodifiable.
  @override
  int get length => _rows.length;

  @override
  set length(int newLength) => _unmodifiable();

  /// The row at [index]. Throws a [RangeError] when [index] is out of
  /// range. O(1).
  @override
  TreeRow<T> operator [](int index) => _rows[index];

  @override
  void operator []=(int index, TreeRow<T> value) => _unmodifiable();

  @override
  set first(TreeRow<T> value) => _unmodifiable();

  @override
  set last(TreeRow<T> value) => _unmodifiable();

  @override
  void add(TreeRow<T> element) => _unmodifiable();

  @override
  void addAll(Iterable<TreeRow<T>> iterable) => _unmodifiable();

  @override
  void insert(int index, TreeRow<T> element) => _unmodifiable();

  @override
  void insertAll(int index, Iterable<TreeRow<T>> iterable) => _unmodifiable();

  @override
  void setAll(int index, Iterable<TreeRow<T>> iterable) => _unmodifiable();

  @override
  bool remove(Object? element) => _unmodifiable();

  @override
  TreeRow<T> removeAt(int index) => _unmodifiable();

  @override
  TreeRow<T> removeLast() => _unmodifiable();

  @override
  void removeWhere(bool Function(TreeRow<T> element) test) => _unmodifiable();

  @override
  void retainWhere(bool Function(TreeRow<T> element) test) => _unmodifiable();

  @override
  void removeRange(int start, int end) => _unmodifiable();

  @override
  void setRange(
    int start,
    int end,
    Iterable<TreeRow<T>> iterable, [
    int skipCount = 0,
  ]) => _unmodifiable();

  @override
  void replaceRange(int start, int end, Iterable<TreeRow<T>> newContents) =>
      _unmodifiable();

  @override
  void fillRange(int start, int end, [TreeRow<T>? fill]) => _unmodifiable();

  @override
  void sort([int Function(TreeRow<T> a, TreeRow<T> b)? compare]) =>
      _unmodifiable();

  @override
  void shuffle([Random? random]) => _unmodifiable();

  @override
  void clear() => _unmodifiable();

  /// The index of the row that shows the node [id], or -1 when that node
  /// is not visible.
  ///
  /// A node that [compactFolders] merged into a row (an intermediate
  /// directory such as `src` in `lib/src/utils`) is found at that row.
  /// Returns -1 for unknown ids, for nodes inside collapsed directories, and
  /// for nodes the filter hides. Runs in O(log rows): one hash lookup, then
  /// a binary search over the rows' pre-order positions.
  int indexOfNode(NodeId id) {
    final position = _source.tree.indexOf(id);
    return position < 0 ? -1 : _indexAt(position);
  }

  /// The row that shows the node [id], or `null` when that node is not
  /// visible.
  ///
  /// Same lookup as [indexOfNode], in O(log rows). For an intermediate
  /// directory of a compacted row this returns that row, whose [TreeRow.id]
  /// is the deepest directory of the chain, not [id].
  TreeRow<T>? rowOf(NodeId id) {
    final index = indexOfNode(id);
    return index < 0 ? null : _rows[index];
  }

  /// The index of the parent row of the row at [index], or `null` for a
  /// top-level row (depth 0).
  ///
  /// The parent row is the nearest visible ancestor: the row that shows the
  /// parent of the row's first chain node. Use it for the left arrow key.
  /// Throws a [RangeError] when [index] is out of range. Runs in
  /// O(log rows).
  int? parentIndexOf(int index) {
    final parent = _rows[index]._parent;
    return parent == null ? null : _indexAt(parent._start);
  }

  /// The index of the first child row of the row at [index], which is
  /// always `index + 1`, or `null` when the row shows no child rows.
  ///
  /// `null` when the row is a file, is collapsed, or has no visible
  /// children. Use it for the right arrow key. Throws a [RangeError] when
  /// [index] is out of range. O(1).
  int? firstChildIndexOf(int index) {
    final depth = _rows[index].depth;
    final next = index + 1;
    // In pre-order, the next row is one level deeper exactly when it is the
    // first child of this row.
    return next < _rows.length && _rows[next].depth == depth + 1 ? next : null;
  }

  /// Returns rows in which the directory [id] is expanded.
  ///
  /// When [id] is shown by a row (directly or as an intermediate directory
  /// of a compacted row), the row's [TreeRow.node] is expanded and its newly
  /// visible descendants are inserted right after it; every other row is
  /// the identical object as before. When [id] is a directory that is not
  /// visible (inside a collapsed directory, or hidden by the filter), only
  /// [expansion] changes and the rows stay the same. Returns these rows
  /// when [id] is unknown, is a file, or is already expanded.
  ///
  /// The result equals `tree.flatten(expansion: result.expansion, filter:
  /// filter, expandMatches: false, compactFolders: compactFolders)`. Runs in
  /// O(log rows + inserted rows) node visits without calling the filter,
  /// plus copying the row list and the expansion state.
  ///
  /// (Named `expandNode` rather than `expand` because a [List] already has
  /// [Iterable.expand].)
  @useResult
  TreeRows<T> expandNode(NodeId id) => _update(id, expand: true);

  /// Returns rows in which the directory [id] is collapsed.
  ///
  /// When [id] is shown by a row (directly or as an intermediate directory
  /// of a compacted row), the row's [TreeRow.node] is collapsed and the
  /// contiguous block of its descendant rows is removed; every other row is
  /// the identical object as before. Descendants keep their own expansion,
  /// so expanding again restores them. When [id] is a directory that is not
  /// visible, only [expansion] changes. Returns these rows when [id] is
  /// unknown, is a file, or is already collapsed.
  ///
  /// The result equals `tree.flatten(expansion: result.expansion, filter:
  /// filter, expandMatches: false, compactFolders: compactFolders)`. Runs in
  /// O(log rows) node visits without calling the filter, plus copying the
  /// row list and the expansion state.
  @useResult
  TreeRows<T> collapseNode(NodeId id) => _update(id, expand: false);

  /// Returns rows in which the directory [id] has the opposite state:
  /// [collapseNode] when it is expanded, [expandNode] otherwise.
  ///
  /// This is the click handler of an expand arrow. For an id inside a
  /// visible compacted row, the state that flips is the state of the row's
  /// [TreeRow.node]. Returns these rows when [id] is unknown or a file. Same
  /// complexity as [expandNode] and [collapseNode].
  @useResult
  TreeRows<T> toggleNode(NodeId id) => _update(id, expand: null);

  /// Returns the rows for [expansion], with the same [tree], [filter], and
  /// [compactFolders], recomputed from scratch.
  ///
  /// [expansion] is used as given: matches are not revealed again. Use it to
  /// apply a state built elsewhere, such as [ExpansionState.expandSubtree]
  /// or a state restored from JSON. Returns these rows when the given state
  /// equals the current one. The filter is not called again; the match
  /// results of the original flatten are reused. Runs in O(rows) plus one
  /// hash lookup per directory row.
  @useResult
  TreeRows<T> withExpansion(ExpansionState expansion) {
    if (expansion == this.expansion) return this;
    return TreeRows<T>._(_source, expansion, _source.buildRows(expansion));
  }

  TreeRows<T> _update(NodeId id, {required bool? expand}) {
    final tree = _source.tree;
    final position = tree.indexOf(id);
    if (position < 0 || !tree.nodes[position].isDirectory) return this;
    final index = _indexAt(position);
    if (index < 0) {
      // A hidden directory: its state matters only once it becomes visible.
      final current = expansion.isExpanded(id);
      final target = expand ?? !current;
      if (target == current) return this;
      return TreeRows<T>._(
        _source,
        expansion.setExpanded(id, expanded: target),
        _rows,
      );
    }
    final row = _rows[index];
    final target = expand ?? !row.isExpanded;
    if (target == row.isExpanded) return this;
    final nextExpansion = expansion.setExpanded(row.node.id, expanded: target);
    final block = <TreeRow<T>>[row._withExpanded(expanded: target)];
    // The old block is the row plus, when it was expanded, its visible
    // descendants, which are exactly the following rows positioned before
    // the end of the row's subtree.
    final int blockEnd;
    if (target) {
      _source.emitChildren(block, nextExpansion, block.first);
      blockEnd = index + 1;
    } else {
      blockEnd = row.hasChildren
          ? _firstIndexFrom(index + 1, _source.subtreeEnd(row._start))
          : index + 1;
    }
    final length = _rows.length - (blockEnd - index) + block.length;
    final rows = List<TreeRow<T>>.filled(length, block.first)
      ..setRange(0, index, _rows)
      ..setRange(index, index + block.length, block)
      ..setRange(index + block.length, length, _rows, blockEnd);
    return TreeRows<T>._(_source, nextExpansion, rows);
  }

  /// The index of the row whose chain covers pre-order [position], or -1.
  int _indexAt(int position) {
    final rows = _rows;
    var low = 0;
    var high = rows.length - 1;
    var found = -1;
    while (low <= high) {
      final middle = low + (high - low) ~/ 2;
      if (rows[middle]._start <= position) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found >= 0 && rows[found]._end >= position ? found : -1;
  }

  /// The first row index at or after [from] whose pre-order start is at or
  /// after [position]; the length when there is none.
  int _firstIndexFrom(int from, int position) {
    var low = from;
    var high = _rows.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (_rows[middle]._start < position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static Never _unmodifiable() => throw UnsupportedError(
    'TreeRows is unmodifiable; derive new rows with expandNode, '
    'collapseNode, toggleNode, or withExpansion.',
  );
}

/// Flattens [tree]; the implementation of [DirectoryTree.flatten].
///
/// Package-internal: call [DirectoryTree.flatten] instead.
@internal
TreeRows<T> flattenTree<T>(
  DirectoryTree<T> tree, {
  required ExpansionState expansion,
  required TreeFilter? filter,
  required bool expandMatches,
  required bool compactFolders,
}) {
  final source = _RowSource<T>(tree, filter, compactFolders: compactFolders);
  final effective = expandMatches ? source.revealMatches(expansion) : expansion;
  return TreeRows<T>._(source, effective, source.buildRows(effective));
}

/// The rows that [DirectoryTree.render] prints: the rows of
/// `tree.flatten(expansion: expansion, filter: filter, compactFolders:
/// compactFolders)` whose depth is at most [maxDepth] (all when `null`).
///
/// Rows deeper than [maxDepth] are never built. Package-internal.
@internal
List<TreeRow<T>> renderRows<T>(
  DirectoryTree<T> tree, {
  required ExpansionState expansion,
  required TreeFilter? filter,
  required bool compactFolders,
  required int? maxDepth,
}) {
  if (maxDepth != null && maxDepth < 0) return <TreeRow<T>>[];
  final source = _RowSource<T>(tree, filter, compactFolders: compactFolders);
  return source.buildRows(source.revealMatches(expansion), maxDepth: maxDepth);
}

/// What one flatten computes once and every [TreeRows] derived from it
/// shares: the tree, the view options, and the filter results.
///
/// Positions are pre-order indexes into [DirectoryTree.nodes]. Without a
/// filter, children and siblings are found from the tree structure, using
/// [DirectoryTree.subtreeSizeOf] to skip collapsed subtrees. With a filter,
/// two pointer arrays link each node to its first child and its next
/// sibling that are visible under the filter (that match or contain a
/// match), so walking visible rows never touches hidden nodes and never
/// calls the filter again.
final class _RowSource<T> {
  _RowSource._(
    this.tree,
    this.filter,
    this.compactFolders,
    this._firstRoot,
    this._selfMatch,
    this._firstVisibleChild,
    this._nextVisibleSibling,
  ) : _nodes = tree.nodes;

  factory _RowSource(
    DirectoryTree<T> tree,
    TreeFilter? filter, {
    required bool compactFolders,
  }) {
    final nodes = tree.nodes;
    final count = nodes.length;
    if (filter == null || filter.matchesAll) {
      return _RowSource<T>._(
        tree,
        null,
        compactFolders,
        count == 0 ? -1 : 0,
        null,
        null,
        null,
      );
    }
    // Pass 1, in pre-order: call the filter once per node and find each
    // node's parent position with a stack of the last position per depth.
    final selfMatch = Uint8List(count);
    final parents = Int32List(count);
    final lastAtDepth = <int>[];
    for (var index = 0; index < count; index++) {
      final node = nodes[index];
      if (filter.matches(node)) selfMatch[index] = 1;
      final depth = node.depth;
      parents[index] = depth == 0 ? -1 : lastAtDepth[depth - 1];
      if (depth < lastAtDepth.length) {
        lastAtDepth[depth] = index;
      } else {
        lastAtDepth.add(index);
      }
    }
    // Pass 2, in reverse pre-order: a node's descendants come before the
    // node itself, so when we reach a node we already know whether its
    // subtree has a match (it matches, or it got a visible child). Linking
    // each visible node in front of its parent's list builds the sibling
    // chains in forward order.
    final firstVisibleChild = Int32List(count)..fillRange(0, count, -1);
    final nextVisibleSibling = Int32List(count)..fillRange(0, count, -1);
    var firstRoot = -1;
    for (var index = count - 1; index >= 0; index--) {
      if (selfMatch[index] == 0 && firstVisibleChild[index] < 0) continue;
      final parent = parents[index];
      if (parent < 0) {
        nextVisibleSibling[index] = firstRoot;
        firstRoot = index;
      } else {
        nextVisibleSibling[index] = firstVisibleChild[parent];
        firstVisibleChild[parent] = index;
      }
    }
    return _RowSource<T>._(
      tree,
      filter,
      compactFolders,
      firstRoot,
      selfMatch,
      firstVisibleChild,
      nextVisibleSibling,
    );
  }

  final DirectoryTree<T> tree;
  final List<TreeNode<T>> _nodes;

  /// The effective filter: `null` when absent or [TreeFilter.matchesAll].
  final TreeFilter? filter;
  final bool compactFolders;

  /// The position of the first visible top-level node, or -1.
  final int _firstRoot;

  // Filter results by position; all three are null without a filter.
  // _selfMatch[i] is 1 when the filter matched node i. _firstVisibleChild[i]
  // is the first child of node i whose subtree has a match (-1 if none), so
  // it is also ">= 0 when a strict descendant of i matches".
  // _nextVisibleSibling[i] is the next such sibling of a visible node i.
  final Uint8List? _selfMatch;
  final Int32List? _firstVisibleChild;
  final Int32List? _nextVisibleSibling;

  /// [expansion] with every ancestor of a filter match expanded; [expansion]
  /// itself without a filter or when nothing changes.
  ExpansionState revealMatches(ExpansionState expansion) {
    final firstVisibleChild = _firstVisibleChild;
    if (firstVisibleChild == null) return expansion;
    return expansion.expandAll(<NodeId>[
      for (var index = 0; index < firstVisibleChild.length; index++)
        if (firstVisibleChild[index] >= 0) _nodes[index].id,
    ]);
  }

  /// The rows of the whole view, top-level rows first, down to [maxDepth].
  List<TreeRow<T>> buildRows(ExpansionState expansion, {int? maxDepth}) {
    final rows = <TreeRow<T>>[];
    _emit(rows, expansion, null, _firstRoot, _nodes.length, maxDepth);
    return rows;
  }

  /// Appends the visible descendant rows of [row], which must be expanded.
  void emitChildren(
    List<TreeRow<T>> out,
    ExpansionState expansion,
    TreeRow<T> row,
  ) {
    if (!row.hasChildren) return;
    final end = _nextVisibleSibling == null ? subtreeEnd(row._start) : 0;
    _emit(out, expansion, row, firstChild(row._end), end, null);
  }

  /// One past the last position of the subtree at [position].
  int subtreeEnd(int position) {
    final node = _nodes[position];
    return node is DirectoryNode<T> && node.children.isNotEmpty
        ? position + tree.subtreeSizeOf(node.id)
        : position + 1;
  }

  /// The position of the first visible child of the node at [position], or
  /// -1 when it has none (always -1 for files).
  int firstChild(int position) {
    final firstVisibleChild = _firstVisibleChild;
    if (firstVisibleChild != null) return firstVisibleChild[position];
    final node = _nodes[position];
    return node is DirectoryNode<T> && node.children.isNotEmpty
        ? position + 1
        : -1;
  }

  /// The position of the deepest node of the row that starts at [start]:
  /// [start] itself unless [compactFolders] merges single-child directory
  /// chains. A directory's only child directly follows it in pre-order.
  int _chainEnd(int start) {
    var end = start;
    if (!compactFolders) return end;
    for (;;) {
      final node = _nodes[end];
      if (node is! DirectoryNode<T> ||
          node.children.length != 1 ||
          !_nodes[end + 1].isDirectory) {
        return end;
      }
      end++;
    }
  }

  bool _chainMatches(int start, int end) {
    final selfMatch = _selfMatch;
    if (selfMatch == null) return true;
    for (var position = start; position <= end; position++) {
      if (selfMatch[position] != 0) return true;
    }
    return false;
  }

  /// Appends to [out], in pre-order, the rows of the sibling list that
  /// starts at position [first] (with parent row [parent]) and every
  /// visible row below them.
  ///
  /// Iterative, so the depth of the tree never limits it. [end] is one past
  /// the parent's subtree; it is only used without a filter, where a
  /// sibling is the position after the previous sibling's subtree. Rows at
  /// [maxDepth] are not descended into.
  void _emit(
    List<TreeRow<T>> out,
    ExpansionState expansion,
    TreeRow<T>? parent,
    int first,
    int end,
    int? maxDepth,
  ) {
    if (first < 0) return;
    final nodes = _nodes;
    final nextVisibleSibling = _nextVisibleSibling;
    final stack = <_Frame<T>>[_Frame<T>(parent, first, end)];
    while (stack.isNotEmpty) {
      final frame = stack.last;
      final start = frame.next;
      if (start < 0) {
        stack.removeLast();
        continue;
      }
      // A chain's nodes nest, so its subtree ends where the first node's
      // subtree ends; that is also where the deepest node's children end.
      var childEnd = 0;
      if (nextVisibleSibling == null) {
        childEnd = subtreeEnd(start);
        frame.next = childEnd < frame.end ? childEnd : -1;
      } else {
        frame.next = nextVisibleSibling[start];
      }
      final chainEnd = _chainEnd(start);
      final node = nodes[chainEnd];
      final rowParent = frame.parent;
      final depth = rowParent == null ? 0 : rowParent.depth + 1;
      final childStart = firstChild(chainEnd);
      final isExpanded = node.isDirectory && expansion.isExpanded(node.id);
      List<TreeNode<T>>? chain;
      String? label;
      if (chainEnd != start) {
        chain = List<TreeNode<T>>.unmodifiable(
          nodes.getRange(start, chainEnd + 1),
        );
        label = _joinLabels(chain);
      }
      final row = TreeRow<T>._(
        node: node,
        depth: depth,
        isExpanded: isExpanded,
        hasChildren: childStart >= 0,
        isLast: frame.next < 0,
        isMatch: _chainMatches(start, chainEnd),
        parent: rowParent,
        start: start,
        chain: chain,
        label: label,
      );
      out.add(row);
      if (isExpanded &&
          childStart >= 0 &&
          (maxDepth == null || depth < maxDepth)) {
        stack.add(_Frame<T>(row, childStart, childEnd));
      }
    }
  }

  static String _joinLabels(List<TreeNode<Object?>> chain) {
    final buffer = StringBuffer();
    var previous = '';
    for (final node in chain) {
      // Path roots such as '/' already end with the separator.
      if (buffer.isNotEmpty && !previous.endsWith('/')) buffer.write('/');
      previous = node.label;
      buffer.write(previous);
    }
    return buffer.toString();
  }
}

/// A sibling list being walked by [_RowSource._emit]: the parent row, the
/// position of the next sibling to emit (-1 when done), and the end of the
/// parent's subtree.
final class _Frame<T> {
  _Frame(this.parent, this.next, this.end);

  final TreeRow<T>? parent;
  int next;
  final int end;
}
