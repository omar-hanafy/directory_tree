import 'dart:collection';

import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:meta/meta.dart';

/// How many nodes a [SelectionState] may hold at once.
enum SelectionMode {
  /// At most one selected id. Operations that would select more keep only
  /// one id, and [SelectionState.check] on a directory with several leaves
  /// throws a [StateError].
  single,

  /// Any number of selected ids, with range selection through
  /// [SelectionState.extendTo].
  multiple,
}

/// The checkbox state of a node, as computed by [SelectionState.checkStateOf]
/// and [SelectionState.checkStates].
enum CheckState {
  /// No leaf in the node's subtree is selected.
  unchecked,

  /// Some, but not all, leaves in the node's subtree are selected. Only
  /// directories with children can be partial.
  partial,

  /// Every leaf in the node's subtree is selected.
  checked,
}

/// An immutable set of selected [NodeId]s with a [mode] and a range
/// [anchor], plus tri-state checkbox semantics over a [DirectoryTree].
///
/// Use it to back list selection (click, ctrl-click with [toggle],
/// shift-click with [extendTo]) and checkbox trees ([check], [uncheck],
/// [toggleCheck], [checkStates]) in a UI. Every operation returns a new
/// state and leaves this one untouched; an operation that changes nothing
/// returns this same instance, so `identical(next, state)` is a cheap
/// "nothing changed" test.
///
/// The state stores ids, not nodes, so it is independent of any one tree.
/// Ids survive [DirectoryTree.rebuild]; call [prune] after a rebuild to drop
/// ids whose nodes are gone. Methods that take a tree accept any
/// `DirectoryTree<T>` and only read its structure.
///
/// ### Checkbox semantics
/// Checks are defined over leaves: files and directories without children.
/// A leaf is [CheckState.checked] when its id is selected, otherwise
/// [CheckState.unchecked]. A directory with children is checked when every
/// leaf in its subtree is selected, unchecked when none is, and
/// [CheckState.partial] otherwise. The ids of directories with children can
/// be in [selected] (for example from [select]), but never affect a check
/// state.
///
/// ```dart
/// final tree = DirectoryTree.fromPaths(['/r/a.txt', '/r/b.txt']);
/// var selection = const SelectionState.empty(mode: SelectionMode.multiple);
/// selection = selection.check(tree, tree.nodeAt('/r/a.txt')!.id);
/// print(selection.checkStateOf(tree, tree.roots.single)); // CheckState.partial
/// ```
///
/// Persist a state with [toJson] and restore it with
/// [SelectionState.fromJson].
@immutable
final class SelectionState {
  /// Creates a state with nothing selected and no [anchor].
  ///
  /// [mode] defaults to [SelectionMode.single].
  const SelectionState.empty({this.mode = SelectionMode.single})
    : _selected = const <NodeId>{},
      anchor = null;

  /// Creates a state with the [selected] ids and an optional [anchor].
  ///
  /// Duplicate ids collapse; [selected] keeps the first-occurrence order.
  /// The [anchor] need not be selected. The ids are not checked against any
  /// tree; see [prune].
  ///
  /// Throws an [ArgumentError] when [mode] is [SelectionMode.single] and
  /// [selected] holds more than one distinct id.
  factory SelectionState({
    SelectionMode mode = SelectionMode.single,
    Iterable<NodeId> selected = const [],
    NodeId? anchor,
  }) {
    final ids = LinkedHashSet<NodeId>.of(selected);
    if (mode == SelectionMode.single && ids.length > 1) {
      throw ArgumentError(
        'single mode allows at most one selected id, got ${ids.length}',
        'selected',
      );
    }
    return SelectionState._(mode, ids, anchor);
  }

  /// Restores a state written by [toJson].
  ///
  /// Expects a map with `'mode'` (`'single'` or `'multiple'`), `'selected'`
  /// (a list of id strings, in any order), and `'anchor'` (an id string or
  /// `null`; a missing key means `null`). Other keys are ignored. The ids are
  /// wrapped in [NodeId] as they are; they are not validated against any
  /// tree.
  ///
  /// Throws a [FormatException] when a key is missing or has the wrong type,
  /// or `'mode'` names an unknown mode. Throws an [ArgumentError] when the
  /// mode is single and more than one distinct id is listed, as the
  /// [SelectionState.new] constructor does.
  factory SelectionState.fromJson(Map<String, Object?> json) {
    final modeName = json['mode'];
    // Plain == comparisons instead of a switch with string patterns: dart2wasm
    // compiles such a switch over an Object? as an unchecked String cast, so
    // a non-string mode would trap instead of reaching the error below.
    final SelectionMode mode;
    if (modeName == 'single') {
      mode = SelectionMode.single;
    } else if (modeName == 'multiple') {
      mode = SelectionMode.multiple;
    } else {
      throw FormatException(
        "SelectionState JSON 'mode' must be 'single' or 'multiple'",
        modeName,
      );
    }
    final selectedJson = json['selected'];
    if (selectedJson is! List<Object?>) {
      throw FormatException(
        "SelectionState JSON 'selected' must be a list of strings",
        selectedJson,
      );
    }
    final selected = <NodeId>[];
    for (final value in selectedJson) {
      if (value is! String) {
        throw FormatException(
          "SelectionState JSON 'selected' must be a list of strings",
          value,
        );
      }
      selected.add(NodeId(value));
    }
    final anchorJson = json['anchor'];
    if (anchorJson != null && anchorJson is! String) {
      throw FormatException(
        "SelectionState JSON 'anchor' must be a string or null",
        anchorJson,
      );
    }
    return SelectionState(
      mode: mode,
      selected: selected,
      anchor: anchorJson == null ? null : NodeId(anchorJson as String),
    );
  }

  // [selected] must already satisfy the mode's size limit and is not copied;
  // callers pass a fresh set they no longer touch.
  SelectionState._(this.mode, Set<NodeId> selected, this.anchor)
    : _selected = UnmodifiableSetView<NodeId>(selected);

  /// Whether at most one id ([SelectionMode.single]) or any number of ids
  /// ([SelectionMode.multiple]) can be selected.
  ///
  /// Change it with [withMode].
  final SelectionMode mode;

  final Set<NodeId> _selected;

  /// The selected ids, in the order they were added. Unmodifiable.
  ///
  /// May contain ids that are not in a given tree (see [prune]) and ids of
  /// directories with children (which do not affect [checkStates]).
  Set<NodeId> get selected => _selected;

  /// The pivot for range selection with [extendTo], or `null`.
  ///
  /// [select] and, in [SelectionMode.multiple], [toggle] move it to the
  /// clicked id; [extendTo], [addAll], [removeAll], [check], and [uncheck]
  /// keep it; [clear] removes it; [withMode] may move or remove it when
  /// switching to [SelectionMode.single]. The anchor need not be selected.
  final NodeId? anchor;

  /// Whether [id] is selected. O(1).
  bool isSelected(NodeId id) => _selected.contains(id);

  /// Whether nothing is selected. The [anchor] may still be set.
  bool get isEmpty => _selected.isEmpty;

  /// The number of selected ids.
  int get length => _selected.length;

  /// Selects exactly [id] and makes it the [anchor] (a plain click).
  ///
  /// Works the same in both modes. Returns this state when [id] is already
  /// the only selected id and the anchor. O(1).
  @useResult
  SelectionState select(NodeId id) {
    if (anchor == id && _selected.length == 1 && _selected.contains(id)) {
      return this;
    }
    return SelectionState._(mode, <NodeId>{id}, id);
  }

  /// Flips [id] in or out of the selection (a ctrl-click).
  ///
  /// In [SelectionMode.multiple] the other ids are kept and [id] becomes the
  /// [anchor] either way; runs in O(length). In [SelectionMode.single] a
  /// selected [id] gives [clear], and any other id gives [select].
  @useResult
  SelectionState toggle(NodeId id) {
    if (mode == SelectionMode.single) {
      return _selected.contains(id) ? clear() : select(id);
    }
    final next = LinkedHashSet<NodeId>.of(_selected);
    if (!next.remove(id)) next.add(id);
    return SelectionState._(mode, next, id);
  }

  /// Selects the range from [anchor] to [id] in [order], inclusive (a
  /// shift-click).
  ///
  /// [order] is the sequence the user sees, usually the ids of the visible
  /// rows. The new selection is exactly the ids from the first of [anchor]
  /// and [id] in [order] up to the other one, replacing the old selection;
  /// the anchor is kept, so repeated calls pivot around the same id.
  ///
  /// Falls back to [select] of [id] (which moves the anchor) in
  /// [SelectionMode.single], when there is no anchor, and when [anchor] or
  /// [id] is not in [order]. Iterates [order] once and stops at the end of
  /// the range, so it runs in O(position of the range end). Returns this
  /// state when the selection would not change.
  @useResult
  SelectionState extendTo(NodeId id, Iterable<NodeId> order) {
    final pivot = anchor;
    if (mode == SelectionMode.single || pivot == null) return select(id);
    final range = <NodeId>{};
    NodeId? closing;
    var found = false;
    for (final current in order) {
      if (closing == null) {
        if (current != pivot && current != id) continue;
        closing = current == pivot ? id : pivot;
      }
      range.add(current);
      if (current == closing) {
        found = true;
        break;
      }
    }
    if (!found) return select(id);
    if (_sameIds(range)) return this;
    return SelectionState._(mode, range, pivot);
  }

  /// Adds [ids] to the selection, keeping the [anchor].
  ///
  /// In [SelectionMode.multiple] the result is the union, with new ids
  /// appended in [ids] order. In [SelectionMode.single] only the last id of
  /// [ids] is kept and it replaces the current selection. Empty [ids], or
  /// ids that are all selected already, return this state. Runs in
  /// O(length + number of ids).
  @useResult
  SelectionState addAll(Iterable<NodeId> ids) {
    if (mode == SelectionMode.single) {
      NodeId? last;
      for (final id in ids) {
        last = id;
      }
      if (last == null) return this;
      if (_selected.length == 1 && _selected.contains(last)) return this;
      return SelectionState._(mode, <NodeId>{last}, anchor);
    }
    LinkedHashSet<NodeId>? next;
    for (final id in ids) {
      if (next == null) {
        if (_selected.contains(id)) continue;
        next = LinkedHashSet<NodeId>.of(_selected);
      }
      next.add(id);
    }
    return next == null ? this : SelectionState._(mode, next, anchor);
  }

  /// Removes [ids] from the selection, keeping the [anchor] even when it is
  /// removed.
  ///
  /// Ids that are not selected are ignored; when none of [ids] is selected
  /// this state is returned. Runs in O(length + number of ids).
  @useResult
  SelectionState removeAll(Iterable<NodeId> ids) {
    LinkedHashSet<NodeId>? next;
    for (final id in ids) {
      if (next == null) {
        if (!_selected.contains(id)) continue;
        next = LinkedHashSet<NodeId>.of(_selected);
      }
      next.remove(id);
    }
    return next == null ? this : SelectionState._(mode, next, anchor);
  }

  /// Deselects everything and removes the [anchor], keeping the [mode].
  ///
  /// Returns this state when it is already empty without an anchor. O(1).
  @useResult
  SelectionState clear() {
    if (_selected.isEmpty && anchor == null) return this;
    return SelectionState.empty(mode: mode);
  }

  /// Switches to [mode].
  ///
  /// Switching to [SelectionMode.multiple] keeps the selection and anchor
  /// unchanged.
  ///
  /// Switching to [SelectionMode.single] keeps at most one id, chosen in
  /// this order:
  /// 1. the [anchor], when it is selected;
  /// 2. otherwise the only selected id, when exactly one is selected; it
  ///    also becomes the anchor;
  /// 3. otherwise nothing: the selection and the anchor are cleared, since
  ///    no single id stands out among several (or none) selected.
  ///
  /// Returns this state when [mode] is the current mode. O(length).
  @useResult
  SelectionState withMode(SelectionMode mode) {
    if (mode == this.mode) return this;
    if (mode == SelectionMode.multiple) {
      return SelectionState._(
        mode,
        LinkedHashSet<NodeId>.of(_selected),
        anchor,
      );
    }
    final pivot = anchor;
    if (pivot != null && _selected.contains(pivot)) {
      return SelectionState._(mode, <NodeId>{pivot}, pivot);
    }
    if (_selected.length == 1) {
      final only = _selected.single;
      return SelectionState._(mode, <NodeId>{only}, only);
    }
    return SelectionState.empty(mode: mode);
  }

  /// Drops the selected ids, and the [anchor], that [tree] does not contain.
  ///
  /// Call it after a [DirectoryTree.rebuild] so the selection only names
  /// existing nodes. Returns this state when every id and the anchor are in
  /// [tree]. Runs in O(length).
  @useResult
  SelectionState prune(DirectoryTree<Object?> tree) {
    final pivot = anchor;
    final keepAnchor = pivot == null || tree.contains(pivot);
    LinkedHashSet<NodeId>? next;
    for (final id in _selected) {
      if (tree.contains(id)) continue;
      next ??= LinkedHashSet<NodeId>.of(_selected);
      next.remove(id);
    }
    if (next == null && keepAnchor) return this;
    return SelectionState._(
      mode,
      next ?? LinkedHashSet<NodeId>.of(_selected),
      keepAnchor ? pivot : null,
    );
  }

  /// The checkbox state of the node [id] in [tree].
  ///
  /// See the class documentation for the rules. Returns
  /// [CheckState.unchecked] for ids that are not in [tree]. Runs in
  /// O(subtree size) and stops early once the result is
  /// [CheckState.partial]; to get the state of many nodes, use
  /// [checkStates].
  CheckState checkStateOf(DirectoryTree<Object?> tree, NodeId id) {
    final index = tree.indexOf(id);
    if (index < 0) return CheckState.unchecked;
    final nodes = tree.nodes;
    final end = index + tree.subtreeSizeOf(id);
    var anySelected = false;
    var anyUnselected = false;
    for (var i = index; i < end; i++) {
      final node = nodes[i];
      if (!_isLeaf(node)) continue;
      if (_selected.contains(node.id)) {
        anySelected = true;
      } else {
        anyUnselected = true;
      }
      if (anySelected && anyUnselected) return CheckState.partial;
    }
    return anySelected ? CheckState.checked : CheckState.unchecked;
  }

  /// The checkbox state of every node in [tree], keyed by id in
  /// [DirectoryTree.nodes] order.
  ///
  /// Gives the same result as calling [checkStateOf] for each node, but in
  /// one O(n) pass over the tree, without recursion, so it is safe for very
  /// deep trees. The map is unmodifiable and empty for an empty tree.
  Map<NodeId, CheckState> checkStates(DirectoryTree<Object?> tree) {
    final nodes = tree.nodes;
    final count = nodes.length;
    // Leaf totals and selected-leaf totals per pre-order index. Children sit
    // after their parent in pre-order, so walking backwards finishes every
    // subtree before its parent is visited.
    final leaves = List<int>.filled(count, 0);
    final selectedLeaves = List<int>.filled(count, 0);
    for (var i = count - 1; i >= 0; i--) {
      final node = nodes[i];
      if (_isLeaf(node)) {
        leaves[i] = 1;
        if (_selected.contains(node.id)) selectedLeaves[i] = 1;
      }
      final parent = node.parent;
      if (parent != null) {
        final parentIndex = tree.indexOf(parent);
        leaves[parentIndex] += leaves[i];
        selectedLeaves[parentIndex] += selectedLeaves[i];
      }
    }
    final states = <NodeId, CheckState>{};
    for (var i = 0; i < count; i++) {
      final selectedCount = selectedLeaves[i];
      states[nodes[i].id] = selectedCount == 0
          ? CheckState.unchecked
          : selectedCount == leaves[i]
          ? CheckState.checked
          : CheckState.partial;
    }
    return UnmodifiableMapView<NodeId, CheckState>(states);
  }

  /// Selects every leaf in the subtree of [id] (just [id] when it is a
  /// leaf), keeping the [anchor].
  ///
  /// Afterwards [checkStateOf] gives [CheckState.checked] for [id]. Selected
  /// ids outside the subtree are kept in [SelectionMode.multiple]; in
  /// [SelectionMode.single] the one leaf replaces the selection. Returns
  /// this state for ids not in [tree] and when nothing changes. Runs in
  /// O(length + subtree size).
  ///
  /// Throws a [StateError] in [SelectionMode.single] when the subtree has
  /// more than one leaf, since a single selection cannot check it.
  @useResult
  SelectionState check(DirectoryTree<Object?> tree, NodeId id) {
    final leaves = _leavesOf(tree, id);
    if (leaves == null) return this;
    if (mode == SelectionMode.single && leaves.length > 1) {
      throw _singleModeError(id, leaves.length);
    }
    return addAll(leaves);
  }

  /// Deselects every leaf in the subtree of [id] (just [id] when it is a
  /// leaf), keeping the [anchor].
  ///
  /// Afterwards [checkStateOf] gives [CheckState.unchecked] for [id]. Ids of
  /// directories with children stay selected. Allowed in both modes. Returns
  /// this state for ids not in [tree] and when nothing changes. Runs in
  /// O(length + subtree size).
  @useResult
  SelectionState uncheck(DirectoryTree<Object?> tree, NodeId id) {
    final leaves = _leavesOf(tree, id);
    return leaves == null ? this : removeAll(leaves);
  }

  /// [uncheck]s [id] when it is [CheckState.checked], otherwise [check]s it
  /// (a click on a checkbox).
  ///
  /// So a partial directory becomes checked. Toggling twice restores the
  /// selection when [id] started checked or unchecked. Returns this state
  /// for ids not in [tree]. Runs in O(length + subtree size).
  ///
  /// Throws a [StateError] in [SelectionMode.single] when the subtree of
  /// [id] has more than one leaf, as [check] does.
  @useResult
  SelectionState toggleCheck(DirectoryTree<Object?> tree, NodeId id) {
    final leaves = _leavesOf(tree, id);
    if (leaves == null) return this;
    if (mode == SelectionMode.single && leaves.length > 1) {
      throw _singleModeError(id, leaves.length);
    }
    return checkStateOf(tree, id) == CheckState.checked
        ? removeAll(leaves)
        : addAll(leaves);
  }

  /// This state as JSON-compatible values, for [SelectionState.fromJson].
  ///
  /// The shape is `{'mode': 'single' | 'multiple', 'selected': [...],
  /// 'anchor': id or null}`, with the selected id strings sorted by code
  /// unit so equal states always encode identically.
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'selected': _sortedValues(),
    'anchor': anchor?.value,
  };

  /// Whether [other] is a [SelectionState] with the same [mode], the same
  /// [selected] ids in any order, and the same [anchor]. O(length).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionState &&
          other.mode == mode &&
          other.anchor == anchor &&
          _sameIds(other._selected);

  /// A hash of [mode], [anchor], and [selected] that ignores selection
  /// order. O(length).
  @override
  int get hashCode =>
      Object.hash(mode, anchor, Object.hashAllUnordered(_selected));

  /// A description such as
  /// `SelectionState(mode: multiple, selected: [/r/a, /r/b], anchor: /r/a)`,
  /// with the ids sorted.
  @override
  String toString() =>
      'SelectionState(mode: ${mode.name}, '
      'selected: [${_sortedValues().join(', ')}], anchor: ${anchor?.value})';

  bool _sameIds(Set<NodeId> other) =>
      other.length == _selected.length && _selected.containsAll(other);

  List<String> _sortedValues() =>
      [for (final id in _selected) id.value]..sort();

  /// The leaves in the subtree of [id] in pre-order, or `null` when [tree]
  /// has no node [id].
  static List<NodeId>? _leavesOf(DirectoryTree<Object?> tree, NodeId id) {
    final index = tree.indexOf(id);
    if (index < 0) return null;
    final nodes = tree.nodes;
    final end = index + tree.subtreeSizeOf(id);
    return [
      for (var i = index; i < end; i++)
        if (_isLeaf(nodes[i])) nodes[i].id,
    ];
  }

  static bool _isLeaf(TreeNode<Object?> node) => switch (node) {
    FileNode<Object?>() => true,
    DirectoryNode<Object?>(:final hasChildren) => !hasChildren,
  };

  static StateError _singleModeError(NodeId id, int leafCount) => StateError(
    'Cannot check ${id.value} in single selection mode: its subtree has '
    '$leafCount leaves, and a single selection holds at most one.',
  );
}
