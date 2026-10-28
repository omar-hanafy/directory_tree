import 'dart:collection';

import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:meta/meta.dart';

/// Which directories of a tree view are expanded: a default plus the ids
/// that differ from it.
///
/// A state is [expandsByDefault] (every directory starts open) or not (every
/// directory starts closed), plus the set of [exceptions] whose state is the
/// opposite. That makes "everything expanded except these" and "everything
/// collapsed except these" equally cheap, and a state stays small however
/// large the tree is.
///
/// States are immutable values keyed by [NodeId]. Because ids are stable
/// across [DirectoryTree.rebuild], a state survives rebuilds; ids that no
/// longer exist are harmless and [prune] drops them. Persist a state with
/// [toJson] and restore it with [ExpansionState.fromJson].
///
/// ```dart
/// final tree = DirectoryTree.fromPaths([
///   '/repo/lib/main.dart',
///   '/repo/README.md',
/// ]);
/// final lib = tree.idOf('/repo/lib')!;
/// var state = const ExpansionState.collapsed();
/// state = state.reveal(tree, lib).expand(lib);
/// print(state.isExpanded(lib)); // true
/// print(state.toJson()); // {default: collapsed, exceptions: [/repo, /repo/lib]}
/// ```
///
/// Pass a state to [DirectoryTree.flatten] or [DirectoryTree.render]. The
/// state itself does not know about trees, so it accepts any id, including
/// ids of files and of nodes that do not exist; views only consult it for
/// directories. Every operation that would not change the state returns this
/// same object, so `identical(next, state)` tells whether anything changed.
@immutable
final class ExpansionState {
  /// A state in which every directory is collapsed.
  ///
  /// Use it for a view that shows only the top-level nodes until the user
  /// opens them.
  const ExpansionState.collapsed()
    : expandsByDefault = false,
      _exceptions = const <NodeId>{};

  /// A state in which every directory is expanded.
  ///
  /// The default of [DirectoryTree.flatten] and [DirectoryTree.render], so a
  /// tree shows in full until something is collapsed.
  const ExpansionState.expanded()
    : expandsByDefault = true,
      _exceptions = const <NodeId>{};

  /// A collapsed-by-default state in which exactly the directories in [ids]
  /// are expanded.
  ///
  /// Duplicate ids count once. Copies [ids] in O(number of ids); later
  /// changes to the iterable do not affect the state.
  factory ExpansionState.withExpanded(Iterable<NodeId> ids) =>
      ExpansionState._(false, _copy(ids));

  /// An expanded-by-default state in which exactly the directories in [ids]
  /// are collapsed.
  ///
  /// Duplicate ids count once. Copies [ids] in O(number of ids); later
  /// changes to the iterable do not affect the state.
  factory ExpansionState.withCollapsed(Iterable<NodeId> ids) =>
      ExpansionState._(true, _copy(ids));

  /// Restores a state written by [toJson].
  ///
  /// [json] must have a `default` key whose value is the string `collapsed`
  /// or `expanded`, and an `exceptions` key whose value is a list of id
  /// strings (each the [NodeId.value] of an id). Other keys are ignored and
  /// duplicate ids count once. The ids are not checked against any tree;
  /// call [prune] to drop ids a tree no longer has.
  ///
  /// Throws a [FormatException] when a key is missing or a value has the
  /// wrong type or an unknown `default`. Runs in O(number of exceptions).
  factory ExpansionState.fromJson(Map<String, Object?> json) {
    // Compare with `is String` and `==` rather than switching on the
    // Object? value: dart2wasm compiles a switch over string constants as an
    // unchecked cast, which would crash on a non-string instead of reaching
    // the FormatException below.
    final mode = json['default'];
    final bool expandsByDefault;
    if (mode is String && mode == 'expanded') {
      expandsByDefault = true;
    } else if (mode is String && mode == 'collapsed') {
      expandsByDefault = false;
    } else {
      throw FormatException(
        "ExpansionState JSON needs 'default' set to 'collapsed' or "
        "'expanded', got: $mode",
      );
    }
    final rawExceptions = json['exceptions'];
    if (rawExceptions is! List<Object?>) {
      throw FormatException(
        "ExpansionState JSON needs 'exceptions' set to a list of id "
        'strings, got: $rawExceptions',
      );
    }
    final exceptions = <NodeId>{};
    for (final value in rawExceptions) {
      if (value is! String) {
        throw FormatException(
          "ExpansionState JSON 'exceptions' must contain only strings, "
          'got: $value',
        );
      }
      exceptions.add(NodeId(value));
    }
    return ExpansionState._(
      expandsByDefault,
      UnmodifiableSetView<NodeId>(exceptions),
    );
  }

  const ExpansionState._(this.expandsByDefault, this._exceptions);

  /// Whether directories not listed in [exceptions] are expanded.
  final bool expandsByDefault;

  final Set<NodeId> _exceptions;

  /// The ids whose state differs from the default: the expanded ids when
  /// [expandsByDefault] is false, the collapsed ids when it is true.
  ///
  /// The set is unmodifiable; its iteration order is unspecified (use
  /// [toJson] for a sorted list). It may contain ids that are files or that
  /// a given tree does not have; see [prune].
  Set<NodeId> get exceptions => _exceptions;

  /// Whether the directory [id] is expanded in this state. O(1).
  ///
  /// Answers for any id, including unknown ids and files, from
  /// [expandsByDefault] and [exceptions]; views only ask about directories.
  bool isExpanded(NodeId id) =>
      _exceptions.contains(id) ? !expandsByDefault : expandsByDefault;

  /// Returns a state in which [id] is expanded.
  ///
  /// Returns this state when [id] is already expanded. Otherwise copies the
  /// exceptions, in O(number of exceptions). [id] is not checked against any
  /// tree. To open a node's ancestors use [reveal]; to open a whole subtree
  /// use [expandSubtree].
  @useResult
  ExpansionState expand(NodeId id) => setExpanded(id, expanded: true);

  /// Returns a state in which [id] is collapsed.
  ///
  /// Returns this state when [id] is already collapsed. Otherwise copies the
  /// exceptions, in O(number of exceptions). Descendants keep their own
  /// state, so expanding [id] again restores what was open below it; use
  /// [collapseSubtree] to close them too.
  @useResult
  ExpansionState collapse(NodeId id) => setExpanded(id, expanded: false);

  /// Returns a state in which [id] has the opposite of its current state.
  ///
  /// Always returns a new state, built in O(number of exceptions).
  @useResult
  ExpansionState toggle(NodeId id) =>
      setExpanded(id, expanded: !isExpanded(id));

  /// Returns a state in which [id] is expanded when [expanded] is true and
  /// collapsed otherwise.
  ///
  /// Returns this state when [id] already has that state. Otherwise copies
  /// the exceptions, in O(number of exceptions): [id] joins [exceptions]
  /// when the new state differs from [expandsByDefault] and leaves it when
  /// it matches.
  @useResult
  ExpansionState setExpanded(NodeId id, {required bool expanded}) {
    if (isExpanded(id) == expanded) return this;
    final next = Set<NodeId>.of(_exceptions);
    if (expanded == expandsByDefault) {
      next.remove(id);
    } else {
      next.add(id);
    }
    return ExpansionState._(expandsByDefault, UnmodifiableSetView(next));
  }

  /// Returns a state in which every id in [ids] is expanded.
  ///
  /// Returns this state when all of them already are (including when [ids]
  /// is empty). Iterates [ids] once and copies the exceptions at most once,
  /// in O(number of ids + number of exceptions).
  @useResult
  ExpansionState expandAll(Iterable<NodeId> ids) =>
      _setAll(ids, expanded: true);

  /// Returns a state in which every id in [ids] is collapsed.
  ///
  /// Returns this state when all of them already are (including when [ids]
  /// is empty). Iterates [ids] once and copies the exceptions at most once,
  /// in O(number of ids + number of exceptions).
  @useResult
  ExpansionState collapseAll(Iterable<NodeId> ids) =>
      _setAll(ids, expanded: false);

  /// Returns a state in which every ancestor of [id] in [tree] is expanded,
  /// so the node shows in a view of [tree].
  ///
  /// The node itself keeps its state. Use it to scroll to a search result or
  /// a newly selected file. Returns this state when [id] is not in [tree],
  /// is a top-level node, or all its ancestors are already expanded. Runs in
  /// O(depth of [id] + number of exceptions).
  ///
  /// [DirectoryTree.flatten] does this for every filter match when its
  /// `expandMatches` argument is true.
  @useResult
  ExpansionState reveal(DirectoryTree<Object?> tree, NodeId id) =>
      expandAll(tree.ancestorsOf(id).map((node) => node.id));

  /// Returns a state in which [id] and every directory below it in [tree]
  /// are expanded ("expand all" on one folder).
  ///
  /// Returns this state when [id] is not a directory of [tree] (unknown ids
  /// and files) or when nothing changes. Files in the subtree are never
  /// added. In a collapsed-by-default state this adds every directory of the
  /// subtree to [exceptions], in O(subtree size + number of exceptions); in
  /// an expanded-by-default state it removes the subtree's directories from
  /// [exceptions], in O(min(subtree size, number of exceptions)) when nothing
  /// changes and O(number of exceptions) otherwise.
  @useResult
  ExpansionState expandSubtree(DirectoryTree<Object?> tree, NodeId id) =>
      _setSubtree(tree, id, expanded: true);

  /// Returns a state in which [id] and every directory below it in [tree]
  /// are collapsed ("collapse all" on one folder).
  ///
  /// Returns this state when [id] is not a directory of [tree] (unknown ids
  /// and files) or when nothing changes. Files in the subtree are never
  /// added. In an expanded-by-default state this adds every directory of
  /// the subtree to [exceptions], in O(subtree size + number of exceptions);
  /// in a collapsed-by-default state it removes the subtree's directories
  /// from [exceptions], in O(min(subtree size, number of exceptions)) when
  /// nothing changes and O(number of exceptions) otherwise.
  @useResult
  ExpansionState collapseSubtree(DirectoryTree<Object?> tree, NodeId id) =>
      _setSubtree(tree, id, expanded: false);

  /// Returns a state without the exceptions that are not directories of
  /// [tree].
  ///
  /// Drops ids of files and ids the tree does not contain, for example after
  /// a rebuild removed folders, so a persisted state does not grow forever.
  /// The answer of [isExpanded] for directories of [tree] does not change.
  /// Returns this state when every exception is a directory of [tree]. Runs
  /// in O(number of exceptions).
  @useResult
  ExpansionState prune(DirectoryTree<Object?> tree) {
    Set<NodeId>? next;
    for (final id in _exceptions) {
      if (tree[id]?.isDirectory ?? false) continue;
      (next ??= Set<NodeId>.of(_exceptions)).remove(id);
    }
    return next == null
        ? this
        : ExpansionState._(expandsByDefault, UnmodifiableSetView(next));
  }

  /// A JSON-compatible map of this state:
  /// `{'default': 'collapsed' | 'expanded', 'exceptions': [ids]}`.
  ///
  /// The exceptions are the [NodeId.value] strings sorted by code units, so
  /// equal states always encode to identical JSON. Restore the state with
  /// [ExpansionState.fromJson]. Runs in O(k log k) for k exceptions.
  Map<String, Object?> toJson() => <String, Object?>{
    'default': expandsByDefault ? 'expanded' : 'collapsed',
    'exceptions': _sortedValues(),
  };

  /// Whether [other] is an [ExpansionState] with the same
  /// [expandsByDefault] and the same [exceptions], in any order.
  ///
  /// Equal states expand exactly the same ids. Runs in O(number of
  /// exceptions).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ExpansionState ||
        other.expandsByDefault != expandsByDefault ||
        other._exceptions.length != _exceptions.length) {
      return false;
    }
    return other._exceptions.containsAll(_exceptions);
  }

  /// A hash of [expandsByDefault] and [exceptions] that ignores their order.
  /// Runs in O(number of exceptions).
  @override
  int get hashCode =>
      Object.hash(expandsByDefault, Object.hashAllUnordered(_exceptions));

  /// A constructor-like description such as `ExpansionState.collapsed()` or
  /// `ExpansionState.withExpanded([/repo, /repo/lib])`.
  ///
  /// Ids are sorted; after the first 20 the rest are summarized as a count.
  @override
  String toString() {
    if (_exceptions.isEmpty) {
      return expandsByDefault
          ? 'ExpansionState.expanded()'
          : 'ExpansionState.collapsed()';
    }
    const shown = 20;
    final values = _sortedValues();
    final listed = values.length <= shown
        ? values.join(', ')
        : '${values.take(shown).join(', ')}, '
              '... ${values.length - shown} more';
    final name = expandsByDefault ? 'withCollapsed' : 'withExpanded';
    return 'ExpansionState.$name([$listed])';
  }

  List<String> _sortedValues() =>
      [for (final id in _exceptions) id.value]..sort();

  ExpansionState _setAll(Iterable<NodeId> ids, {required bool expanded}) {
    // Exceptions hold the ids whose state differs from the default, so the
    // target state either needs every id present (it is not the default) or
    // absent (it is the default).
    final present = expanded != expandsByDefault;
    Set<NodeId>? next;
    for (final id in ids) {
      if ((next ?? _exceptions).contains(id) == present) continue;
      next ??= Set<NodeId>.of(_exceptions);
      if (present) {
        next.add(id);
      } else {
        next.remove(id);
      }
    }
    return next == null
        ? this
        : ExpansionState._(expandsByDefault, UnmodifiableSetView(next));
  }

  ExpansionState _setSubtree(
    DirectoryTree<Object?> tree,
    NodeId id, {
    required bool expanded,
  }) {
    final node = tree[id];
    if (node == null || !node.isDirectory) return this;
    if (expanded != expandsByDefault) {
      // The target is the exception: every directory of the subtree must be
      // listed.
      return _setAll(_subtreeDirectoryIds(tree, node), expanded: expanded);
    }
    // The target is the default: drop the subtree's directories from the
    // exceptions. Walk whichever side is smaller.
    if (_exceptions.isEmpty) return this;
    if (tree.subtreeSizeOf(id) <= _exceptions.length) {
      return _setAll(_subtreeDirectoryIds(tree, node), expanded: expanded);
    }
    Set<NodeId>? next;
    for (final exception in _exceptions) {
      if (exception != id && !tree.isAncestor(id, exception)) continue;
      if (!(tree[exception]?.isDirectory ?? false)) continue;
      (next ??= Set<NodeId>.of(_exceptions)).remove(exception);
    }
    return next == null
        ? this
        : ExpansionState._(expandsByDefault, UnmodifiableSetView(next));
  }

  static Iterable<NodeId> _subtreeDirectoryIds(
    DirectoryTree<Object?> tree,
    TreeNode<Object?> node,
  ) => <TreeNode<Object?>>[node]
      .followedBy(tree.descendantsOf(node.id))
      .where((node) => node.isDirectory)
      .map((node) => node.id);

  static Set<NodeId> _copy(Iterable<NodeId> ids) =>
      UnmodifiableSetView<NodeId>(Set<NodeId>.of(ids));
}
