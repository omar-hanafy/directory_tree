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
///
/// A row stores only its node, depth, position, and parent row (a view of a
/// million rows allocates a million rows); [hasChildren], [isMatch],
/// [chain], [label], and [guides] are derived when read.
@immutable
final class TreeRow<T> {
  // A row stores four fields (plus the type argument every instance of a
  // generic class carries), which keeps it at 48 bytes on 64-bit VMs: the
  // two flags live in the row's class (see _row), and one field holds the
  // parent row or, for a depth-0 row, the flatten it came from.
  TreeRow._(this.node, this.depth, this._start, this._up);

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

  /// The indentation level: 0 for rows without a parent row, otherwise the
  /// depth of the parent row plus one.
  ///
  /// Equals [TreeNode.depth] of the first node of [chain], minus the number
  /// of ancestor directories that compacted rows absorbed, minus one more
  /// when [TreeRows.showRoots] is false (the children of the top-level nodes
  /// are then the depth-0 rows).
  final int depth;

  /// Whether [node] is a directory that is expanded in
  /// [TreeRows.expansion]; always false for files.
  ///
  /// An expanded row shows its child rows right after it. A directory can be
  /// expanded and still show none when [hasChildren] is false.
  bool get isExpanded => false;

  /// Whether expanding this row would show at least one child row.
  ///
  /// False for files and empty directories. Under a filter, also false for a
  /// directory none of whose children match or contain a match. Use it to
  /// decide whether to draw an expand arrow. Derived from the tree and the
  /// filter results of the flatten when read, in O(depth + length of
  /// [chain]).
  bool get hasChildren => _source.hasChildrenAt(_start, node);

  /// Whether no later sibling row follows this one under the same parent
  /// row (or among the depth-0 rows).
  ///
  /// Siblings hidden by the filter do not count. When [TreeRows.showRoots]
  /// is false, every depth-0 row counts as a sibling of every other, across
  /// top-level nodes, so only the very last depth-0 row is last. Text trees
  /// draw `└── ` instead of `├── ` for the last row; see [TreeStyle].
  bool get isLast => false;

  /// Whether a node of [chain] matched the filter itself, as opposed to
  /// being shown only because a descendant matched.
  ///
  /// True for every row when the rows have no filter. Use it to highlight
  /// matches and dim the ancestors that lead to them. Read from the match
  /// results cached by the flatten (the filter is not called again), in
  /// O(depth + length of [chain]).
  bool get isMatch => _source.isMatchAt(_start);

  /// For each ancestor level, whether a vertical guide line continues
  /// through that column.
  ///
  /// `guides.length == depth`, and `guides[i]` is true when this row's
  /// ancestor row at depth `i` has a later visible sibling (its [isLast] is
  /// false), so the line from that ancestor to its next sibling passes this
  /// row. Text trees draw a pipe for true and a gap for false; see
  /// [DirectoryTree.render].
  ///
  /// Computed from the ancestor rows on each read, in O(depth); keep the
  /// list in a local variable when you read it repeatedly. The list is
  /// unmodifiable.
  List<bool> get guides {
    if (depth == 0) return const <bool>[];
    final guides = List<bool>.filled(depth, false);
    var ancestor = _parent;
    for (var level = depth - 1; level >= 0; level--) {
      guides[level] = !ancestor!.isLast;
      ancestor = ancestor._parent;
    }
    return UnmodifiableListView<bool>(guides);
  }

  /// The nodes this row stands for, outermost first; ends with [node].
  ///
  /// A single node unless [TreeRows.compactFolders] merged a run of
  /// directories that each have exactly one child directory, such as
  /// `lib`, `src`, `utils` shown as one row `lib/src/utils`. Built on each
  /// read, in O(depth + length of the chain). The list is unmodifiable.
  List<TreeNode<T>> get chain {
    final source = _source;
    final end = source.chainEnd(_start);
    return end == _start
        ? List<TreeNode<T>>.unmodifiable(<TreeNode<T>>[node])
        : List<TreeNode<T>>.unmodifiable(
            source.nodes.getRange(_start, end + 1),
          );
  }

  /// The text to display: the [TreeNode.label]s of [chain] joined with `/`.
  ///
  /// For an uncompacted row this is `node.label`, which is the node's name
  /// except for top-level nodes whose names collide (`a/src`, `b/src`). A
  /// `/` is not doubled after a label that already ends with one, so a
  /// compacted POSIX root reads `/usr/lib`, not `//usr/lib`. Derived when
  /// read, in O(depth); a compacted label is joined on each read, in O(its
  /// length).
  String get label {
    final source = _source;
    final end = source.chainEnd(_start);
    return end == _start ? node.label : source.joinLabels(_start, end);
  }

  // Pre-order index (in DirectoryTree.nodes) of the first node of [chain].
  // Chains are contiguous in pre-order, so the row covers the indexes
  // _start.._end, and rows are sorted by _start.
  final int _start;

  // The parent row (a TreeRow) for a row below depth 0, and the flatten it
  // came from (the _RowSource) for a depth-0 row. The parent is always the
  // row object present in the same TreeRows: updates replace a row only
  // together with its whole block of descendant rows.
  final Object _up;

  // The parent row, for [guides] and TreeRows.parentIndexOf; null for a
  // depth-0 row.
  TreeRow<Object?>? get _parent {
    final up = _up;
    return up is TreeRow<Object?> ? up : null;
  }

  // The flatten this row came from: the tree, the view options, and the
  // filter results that the derived properties read. Found above the
  // depth-0 ancestor, in O(depth).
  _RowSource<T> get _source {
    var up = _up;
    while (up is TreeRow<Object?>) {
      up = up._up;
    }
    return up as _RowSource<T>;
  }

  // Pre-order index of [node], the last node of the chain.
  int get _end => _source.chainEnd(_start);

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
        other.isLast != isLast ||
        other.node != node ||
        other.hasChildren != hasChildren ||
        other.isMatch != isMatch) {
      return false;
    }
    final chain = this.chain;
    final otherChain = other.chain;
    if (otherChain.length != chain.length) return false;
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
  /// equally), so it never builds lists; it costs O(depth + chain length)
  /// once the node's own cached hash exists.
  @override
  int get hashCode => Object.hash(
    node,
    depth,
    isExpanded,
    hasChildren,
    isLast,
    isMatch,
    _end - _start,
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
  TreeRow<T> _withExpanded({required bool expanded}) =>
      _row<T>(node, depth, _start, _up, isExpanded: expanded, isLast: isLast);
}

/// Creates a row whose class encodes [isExpanded] and [isLast]; [up] is the
/// parent row, or the [_RowSource] for a depth-0 row.
///
/// A bool field costs a full word per row, and with 16-byte object
/// alignment two more fields would grow every row from 48 to 64 bytes, so
/// the four flag combinations are four classes instead.
TreeRow<T> _row<T>(
  TreeNode<T> node,
  int depth,
  int start,
  Object up, {
  required bool isExpanded,
  required bool isLast,
}) {
  if (isExpanded) {
    return isLast
        ? _ExpandedLastRow<T>(node, depth, start, up)
        : _ExpandedRow<T>(node, depth, start, up);
  }
  return isLast
      ? _LastRow<T>(node, depth, start, up)
      : TreeRow<T>._(node, depth, start, up);
}

final class _ExpandedRow<T> extends TreeRow<T> {
  _ExpandedRow(super.node, super.depth, super._start, super._up) : super._();

  @override
  bool get isExpanded => true;
}

final class _LastRow<T> extends TreeRow<T> {
  _LastRow(super.node, super.depth, super._start, super._up) : super._();

  @override
  bool get isLast => true;
}

final class _ExpandedLastRow<T> extends TreeRow<T> {
  _ExpandedLastRow(super.node, super.depth, super._start, super._up)
    : super._();

  @override
  bool get isExpanded => true;

  @override
  bool get isLast => true;
}

/// The visible rows of a [DirectoryTree] view, in display order, with
/// lookup, keyboard navigation, and incremental expand and collapse.
///
/// Create rows with [DirectoryTree.flatten]. The list holds one [TreeRow]
/// per visible node (or per compacted chain of directories): the tree's
/// pre-order restricted to nodes whose parent row is expanded (top-level
/// nodes are always candidates, unless [showRoots] is false). It is an
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
/// ## Hidden roots
///
/// With [showRoots] false, the top-level nodes produce no rows and count as
/// expanded whatever [expansion] says. Their visible children are the
/// depth-0 rows, in root order and then child order, and all depth-0 rows
/// are siblings for [TreeRow.isLast] and [TreeRow.guides], as if the roots
/// did not exist. A top-level id has no row ([indexOfNode] returns -1), and
/// [expandNode], [collapseNode], and [toggleNode] ignore it. Compacted
/// chains start below the roots. Use it for an explorer of one folder,
/// whose name is a title rather than a row.
///
/// ## Incremental updates
///
/// [expandNode], [collapseNode], and [toggleNode] return new rows that equal
/// what [DirectoryTree.flatten] would return for the updated [expansion]
/// with the same [filter], [compactFolders], and [showRoots] and
/// `expandMatches: false`, but they
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

  // Every element is non-null. The element type is nullable so a flatten
  // can allocate the list once at an upper bound of the row count and trim
  // it (see _RowSource.buildRows) instead of growing it by doubling.
  final List<TreeRow<T>?> _rows;

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

  /// Whether the top-level nodes are rows.
  ///
  /// When false, the top-level nodes count as expanded and their children
  /// are the depth-0 rows; see "Hidden roots" above and
  /// [DirectoryTree.flatten]. [withExpansion] and the incremental updates
  /// keep this setting.
  bool get showRoots => _source.showRoots;

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
  TreeRow<T> operator [](int index) => _rows[index]!;

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
    return index < 0 ? null : _rows[index]!;
  }

  /// The index of the parent row of the row at [index], or `null` for a
  /// top-level row (depth 0).
  ///
  /// The parent row is the nearest visible ancestor: the row that shows the
  /// parent of the row's first chain node. Use it for the left arrow key.
  /// Throws a [RangeError] when [index] is out of range. Runs in
  /// O(log rows).
  int? parentIndexOf(int index) {
    final parent = _rows[index]!._parent;
    return parent == null ? null : _indexAt(parent._start);
  }

  /// The index of the first child row of the row at [index], which is
  /// always `index + 1`, or `null` when the row shows no child rows.
  ///
  /// `null` when the row is a file, is collapsed, or has no visible
  /// children. Use it for the right arrow key. Throws a [RangeError] when
  /// [index] is out of range. O(1).
  int? firstChildIndexOf(int index) {
    final depth = _rows[index]!.depth;
    final next = index + 1;
    // In pre-order, the next row is one level deeper exactly when it is the
    // first child of this row.
    return next < _rows.length && _rows[next]!.depth == depth + 1 ? next : null;
  }

  /// Returns rows in which the directory [id] is expanded.
  ///
  /// When [id] is shown by a row (directly or as an intermediate directory
  /// of a compacted row), the row's [TreeRow.node] is expanded and its newly
  /// visible descendants are inserted right after it; every other row is
  /// the identical object as before. When [id] is a directory that is not
  /// visible (inside a collapsed directory, or hidden by the filter), only
  /// [expansion] changes and the rows stay the same. Returns these rows
  /// when [id] is unknown, is a file, is already expanded, or is a
  /// top-level node while [showRoots] is false (hidden roots always count
  /// as expanded).
  ///
  /// The result equals `tree.flatten(expansion: result.expansion, filter:
  /// filter, expandMatches: false, compactFolders: compactFolders,
  /// showRoots: showRoots)`. Runs in O(log rows + inserted rows) node visits
  /// without calling the filter, plus copying the row list and the
  /// expansion state.
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
  /// unknown, is a file, is already collapsed, or is a top-level node while
  /// [showRoots] is false (hidden roots cannot be collapsed).
  ///
  /// The result equals `tree.flatten(expansion: result.expansion, filter:
  /// filter, expandMatches: false, compactFolders: compactFolders,
  /// showRoots: showRoots)`. Runs in O(log rows) node visits without calling
  /// the filter, plus copying the row list and the expansion state.
  @useResult
  TreeRows<T> collapseNode(NodeId id) => _update(id, expand: false);

  /// Returns rows in which the directory [id] has the opposite state:
  /// [collapseNode] when it is expanded, [expandNode] otherwise.
  ///
  /// This is the click handler of an expand arrow. For an id inside a
  /// visible compacted row, the state that flips is the state of the row's
  /// [TreeRow.node]. Returns these rows when [id] is unknown, is a file, or
  /// is a top-level node while [showRoots] is false. Same complexity as
  /// [expandNode] and [collapseNode].
  @useResult
  TreeRows<T> toggleNode(NodeId id) => _update(id, expand: null);

  /// Returns the rows for [expansion], with the same [tree], [filter],
  /// [compactFolders], and [showRoots], recomputed from scratch.
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
    if (position < 0) return this;
    final node = tree.nodes[position];
    // Hidden roots have no row and always count as expanded.
    if (!node.isDirectory || (node.isRoot && !_source.showRoots)) return this;
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
    final row = _rows[index]!;
    final target = expand ?? !row.isExpanded;
    if (target == row.isExpanded) return this;
    final nextExpansion = expansion.setExpanded(row.node.id, expanded: target);
    final replacement = row._withExpanded(expanded: target);
    final block = <TreeRow<T>?>[replacement];
    // The old block is the row plus, when it was expanded, its visible
    // descendants, which are exactly the following rows positioned before
    // the end of the row's subtree.
    final int blockEnd;
    if (target) {
      _source.emitChildren(block, nextExpansion, replacement);
      blockEnd = index + 1;
    } else {
      blockEnd = _source.hasChildrenAt(row._start, row.node)
          ? _firstIndexFrom(index + 1, _source.subtreeEnd(row._start))
          : index + 1;
    }
    final length = _rows.length - (blockEnd - index) + block.length;
    final rows = List<TreeRow<T>?>.filled(length, null)
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
      if (rows[middle]!._start <= position) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found >= 0 && _source.chainEnd(rows[found]!._start) >= position
        ? found
        : -1;
  }

  /// The first row index at or after [from] whose pre-order start is at or
  /// after [position]; the length when there is none.
  int _firstIndexFrom(int from, int position) {
    var low = from;
    var high = _rows.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (_rows[middle]!._start < position) {
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
  required bool showRoots,
}) {
  final source = _RowSource<T>(
    tree,
    filter,
    compactFolders: compactFolders,
    showRoots: showRoots,
  );
  final effective = expandMatches ? source.revealMatches(expansion) : expansion;
  return TreeRows<T>._(source, effective, source.buildRows(effective));
}

/// The rows that [DirectoryTree.render] prints: the rows of
/// `tree.flatten(expansion: expansion, filter: filter, compactFolders:
/// compactFolders, showRoots: showRoots)` whose depth is at most [maxDepth]
/// (all when `null`).
///
/// Rows deeper than [maxDepth] are never built. Every element of the result
/// is non-null. Package-internal.
@internal
List<TreeRow<T>?> renderRows<T>(
  DirectoryTree<T> tree, {
  required ExpansionState expansion,
  required TreeFilter? filter,
  required bool compactFolders,
  required bool showRoots,
  required int? maxDepth,
}) {
  if (maxDepth != null && maxDepth < 0) return <TreeRow<T>?>[];
  final source = _RowSource<T>(
    tree,
    filter,
    compactFolders: compactFolders,
    showRoots: showRoots,
  );
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
/// calls the filter again. Every depth-0 row references its source, and
/// rows read [TreeRow.hasChildren], [TreeRow.isMatch], and their chain from
/// it.
final class _RowSource<T> {
  _RowSource._(
    this.tree,
    this.filter,
    this.compactFolders,
    this.showRoots,
    this._firstRoot,
    this._visibleCount,
    this._selfMatch,
    this._firstVisibleChild,
    this._nextVisibleSibling,
  ) : nodes = tree.nodes;

  factory _RowSource(
    DirectoryTree<T> tree,
    TreeFilter? filter, {
    required bool compactFolders,
    required bool showRoots,
  }) {
    final nodes = tree.nodes;
    final count = nodes.length;
    if (filter == null || filter.matchesAll) {
      return _RowSource<T>._(
        tree,
        null,
        compactFolders,
        showRoots,
        count == 0 ? -1 : 0,
        count,
        null,
        null,
        null,
      );
    }
    // One pass in pre-order, calling the filter exactly once per node and
    // touching each node object once. open[d] is the open ancestor at depth
    // d of the current node and lastChild[d] its last visible child so far.
    // When the walk reaches a node at depth d, the subtrees of the open
    // nodes at depth d or deeper are complete: such a node is visible when
    // it matches or got a visible child, and a visible node is appended to
    // its parent's list of visible children (or the top-level list).
    // Closing deepest first links children before their parent is decided,
    // and appending in pre-order keeps every list in order, so no per-node
    // parent index is needed.
    final selfMatch = Uint8List(count);
    final firstVisibleChild = Int32List(count)..fillRange(0, count, -1);
    final nextVisibleSibling = Int32List(count)..fillRange(0, count, -1);
    final open = <int>[];
    final lastChild = <int>[];
    var top = -1;
    var firstRoot = -1;
    var lastRoot = -1;
    var visibleCount = 0;
    for (var index = 0; index <= count; index++) {
      // Past the last node, depth 0 closes everything.
      final node = index < count ? nodes[index] : null;
      final depth = node == null ? 0 : node.depth;
      for (; top >= depth; top--) {
        final closing = open[top];
        if (selfMatch[closing] == 0 && firstVisibleChild[closing] < 0) {
          continue;
        }
        visibleCount++;
        if (top == 0) {
          if (lastRoot < 0) {
            firstRoot = closing;
          } else {
            nextVisibleSibling[lastRoot] = closing;
          }
          lastRoot = closing;
        } else {
          final last = lastChild[top - 1];
          if (last < 0) {
            firstVisibleChild[open[top - 1]] = closing;
          } else {
            nextVisibleSibling[last] = closing;
          }
          lastChild[top - 1] = closing;
        }
      }
      if (node == null) break;
      if (filter.matches(node)) selfMatch[index] = 1;
      // In pre-order a node is at most one level below the previous node,
      // so after closing, `depth` is the next free level.
      top = depth;
      if (depth == open.length) {
        open.add(index);
        lastChild.add(-1);
      } else {
        open[depth] = index;
        lastChild[depth] = -1;
      }
    }
    return _RowSource<T>._(
      tree,
      filter,
      compactFolders,
      showRoots,
      firstRoot,
      visibleCount,
      selfMatch,
      firstVisibleChild,
      nextVisibleSibling,
    );
  }

  final DirectoryTree<T> tree;

  /// [DirectoryTree.nodes] of [tree], in pre-order.
  final List<TreeNode<T>> nodes;

  /// The effective filter: `null` when absent or [TreeFilter.matchesAll].
  final TreeFilter? filter;
  final bool compactFolders;

  /// Whether top-level nodes are rows; when false their children are the
  /// depth-0 rows and the roots count as expanded.
  final bool showRoots;

  /// The position of the first visible top-level node, or -1.
  final int _firstRoot;

  /// The number of nodes the filter keeps visible (all nodes without a
  /// filter): an upper bound on the number of rows.
  final int _visibleCount;

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
    // The ancestors of matches are exactly the nodes with a visible child.
    // Collect only those the state does not expand yet, so an expanded
    // state (the default) allocates nothing here.
    List<NodeId>? closed;
    for (var index = 0; index < firstVisibleChild.length; index++) {
      if (firstVisibleChild[index] < 0) continue;
      final id = nodes[index].id;
      if (!expansion.isExpanded(id)) (closed ??= <NodeId>[]).add(id);
    }
    return closed == null ? expansion : expansion.expandAll(closed);
  }

  /// The rows of the whole view, depth-0 rows first, down to [maxDepth].
  ///
  /// Every element of the result is non-null.
  List<TreeRow<T>?> buildRows(ExpansionState expansion, {int? maxDepth}) {
    final rows = <TreeRow<T>?>[];
    // One allocation at an upper bound instead of growth by doubling. The
    // final `length = count` keeps the array when it is mostly used and
    // copies only when the bound overshot by more than three times.
    final capacity = maxDepth == null ? _capacity(expansion) : 0;
    if (capacity > 0) rows.length = capacity;
    final int count;
    if (showRoots) {
      count = _emit(
        rows,
        0,
        expansion,
        null,
        _firstRoot,
        nodes.length,
        -1,
        maxDepth,
      );
    } else {
      // The roots are skipped: the depth-0 rows are their children, walked
      // as one sibling list, starting at the first root that has a visible
      // child.
      final root = _rootWithChildren(_firstRoot);
      count = root < 0
          ? 0
          : _emit(
              rows,
              0,
              expansion,
              null,
              firstChild(root),
              _nextVisibleSibling == null ? subtreeEnd(root) : 0,
              root,
              maxDepth,
            );
    }
    rows.length = count;
    return rows;
  }

  /// Appends the visible descendant rows of [row], which must be expanded,
  /// to [out].
  void emitChildren(
    List<TreeRow<T>?> out,
    ExpansionState expansion,
    TreeRow<T> row,
  ) {
    final first = firstChild(chainEnd(row._start));
    if (first < 0) return;
    final end = _nextVisibleSibling == null ? subtreeEnd(row._start) : 0;
    _emit(out, out.length, expansion, row, first, end, -1, null);
  }

  /// An upper bound on the number of rows for [expansion] that is cheap to
  /// compute and, as far as expansion can tell, at most three times the
  /// actual number, so allocating it never costs more than the walk; 0 when
  /// there is no such bound.
  ///
  /// With a filter the bound is the number of visible nodes (the walk is
  /// O(n) anyway). Without one, it needs a state that expands by default
  /// with few exceptions: every node is a row except the descendants of the
  /// collapsed exceptions. Hidden roots and compacted chains lower the
  /// count further, but those views visit every node they leave out, so the
  /// bound stays within the cost of the walk.
  int _capacity(ExpansionState expansion) {
    if (_firstVisibleChild != null) return _visibleCount;
    if (!expansion.expandsByDefault) return 0;
    final exceptions = expansion.exceptions;
    if (exceptions.length > 64) return 0;
    var largest = 0;
    var total = 0;
    for (final id in exceptions) {
      final hidden = tree.subtreeSizeOf(id) - 1;
      if (hidden <= 0) continue;
      total += hidden;
      if (hidden > largest) largest = hidden;
    }
    final bound = nodes.length - largest;
    return nodes.length - total >= bound ~/ 3 ? bound : 0;
  }

  /// The first root at or after [root], in the hidden-roots walk, that has
  /// a visible child, or -1.
  int _rootWithChildren(int root) {
    var current = root;
    while (current >= 0 && firstChild(current) < 0) {
      current = _nextRoot(
        current,
        _nextVisibleSibling == null ? subtreeEnd(current) : 0,
      );
    }
    return current;
  }

  /// The root after [root] in the hidden-roots walk, or -1: the next visible
  /// top-level node. [rootEnd] is one past [root]'s subtree (only used
  /// without a filter).
  int _nextRoot(int root, int rootEnd) {
    final nextVisibleSibling = _nextVisibleSibling;
    if (nextVisibleSibling != null) return nextVisibleSibling[root];
    return rootEnd < nodes.length ? rootEnd : -1;
  }

  /// One past the last position of the subtree at [position].
  int subtreeEnd(int position) {
    final node = nodes[position];
    return node is DirectoryNode<T> && node.children.isNotEmpty
        ? position + tree.subtreeSizeOf(node.id)
        : position + 1;
  }

  /// The position of the first visible child of the node at [position], or
  /// -1 when it has none (always -1 for files).
  int firstChild(int position) {
    final firstVisibleChild = _firstVisibleChild;
    if (firstVisibleChild != null) return firstVisibleChild[position];
    final node = nodes[position];
    return node is DirectoryNode<T> && node.children.isNotEmpty
        ? position + 1
        : -1;
  }

  /// The position of the deepest node of the row that starts at [start]:
  /// [start] itself unless [compactFolders] merges single-child directory
  /// chains. A directory's only child directly follows it in pre-order.
  int chainEnd(int start) {
    var end = start;
    if (!compactFolders) return end;
    for (;;) {
      final node = nodes[end];
      if (node is! DirectoryNode<T> ||
          node.children.length != 1 ||
          !nodes[end + 1].isDirectory) {
        return end;
      }
      end++;
    }
  }

  /// [TreeRow.hasChildren] of the row that starts at [start] and shows
  /// [node].
  bool hasChildrenAt(int start, TreeNode<T> node) {
    final firstVisibleChild = _firstVisibleChild;
    if (firstVisibleChild == null) {
      return node is DirectoryNode<T> && node.children.isNotEmpty;
    }
    return firstVisibleChild[chainEnd(start)] >= 0;
  }

  /// [TreeRow.isMatch] of the row that starts at [start].
  bool isMatchAt(int start) {
    final selfMatch = _selfMatch;
    if (selfMatch == null) return true;
    final end = chainEnd(start);
    for (var position = start; position <= end; position++) {
      if (selfMatch[position] != 0) return true;
    }
    return false;
  }

  /// The labels of the nodes at positions [start] to [end] joined with `/`,
  /// without doubling a `/` that a label already ends with (path roots such
  /// as `/`).
  String joinLabels(int start, int end) {
    final buffer = StringBuffer();
    var previous = '';
    for (var position = start; position <= end; position++) {
      if (position > start && !previous.endsWith('/')) buffer.write('/');
      previous = nodes[position].label;
      buffer.write(previous);
    }
    return buffer.toString();
  }

  /// Writes, in pre-order, the rows of the sibling list that starts at
  /// [first] (children of [parent], or depth-0 rows when it is `null`) and
  /// every visible row below them into [out], from index [count] on, and
  /// returns the new count.
  ///
  /// Slots below the length of [out] (a presized list) are overwritten;
  /// beyond it rows are added. Iterative, so the depth of the tree never
  /// limits it: one entry per open level in three parallel lists, so the
  /// walk allocates nothing per level. A level's `end` is one past the
  /// parent's subtree; it is only used without a filter, where a sibling is
  /// the position after the previous sibling's subtree. When [root] is a
  /// hidden root, the bottom level continues with the children of the next
  /// root once [root]'s children run out, so all depth-0 rows form one
  /// sibling list. Rows at [maxDepth] are not descended into.
  int _emit(
    List<TreeRow<T>?> out,
    int count,
    ExpansionState expansion,
    TreeRow<T>? parent,
    int first,
    int end,
    int root,
    int? maxDepth,
  ) {
    if (first < 0) return count;
    final capacity = out.length;
    final nextVisibleSibling = _nextVisibleSibling;
    final parents = <TreeRow<T>?>[parent];
    final nexts = <int>[first];
    final ends = <int>[end];
    var top = 0;
    var hiddenRoot = root;
    var written = count;
    while (top >= 0) {
      final start = nexts[top];
      if (start < 0) {
        top--;
        continue;
      }
      // A chain's nodes nest, so its subtree ends where the first node's
      // subtree ends; that is also where the deepest node's children end.
      var childEnd = 0;
      int next;
      if (nextVisibleSibling == null) {
        childEnd = subtreeEnd(start);
        next = childEnd < ends[top] ? childEnd : -1;
      } else {
        next = nextVisibleSibling[start];
      }
      if (next < 0 && top == 0 && hiddenRoot >= 0) {
        // The last child of a hidden root: its next sibling is the first
        // visible child of a later root, if any. This happens before the
        // row is built, so its isLast sees the cross-root sibling.
        hiddenRoot = _rootWithChildren(_nextRoot(hiddenRoot, ends[0]));
        if (hiddenRoot >= 0) {
          next = firstChild(hiddenRoot);
          ends[0] = nextVisibleSibling == null ? subtreeEnd(hiddenRoot) : 0;
        }
      }
      nexts[top] = next;
      final chainEnd = this.chainEnd(start);
      final node = nodes[chainEnd];
      final rowParent = parents[top];
      final depth = rowParent == null ? 0 : rowParent.depth + 1;
      final isExpanded = node.isDirectory && expansion.isExpanded(node.id);
      final row = _row<T>(
        node,
        depth,
        start,
        rowParent ?? this,
        isExpanded: isExpanded,
        isLast: next < 0,
      );
      if (written < capacity) {
        out[written] = row;
      } else {
        out.add(row);
      }
      written++;
      if (!isExpanded || (maxDepth != null && depth >= maxDepth)) continue;
      final childStart = firstChild(chainEnd);
      if (childStart < 0) continue;
      top++;
      if (top == parents.length) {
        parents.add(row);
        nexts.add(childStart);
        ends.add(childEnd);
      } else {
        parents[top] = row;
        nexts[top] = childStart;
        ends[top] = childEnd;
      }
    }
    return written;
  }
}
