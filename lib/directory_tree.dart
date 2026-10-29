/// Deterministic, immutable directory trees for pure Dart.
///
/// Feed a list of paths (from a file picker, `git ls-files`, a server
/// response, or a scanner) and get an indexed tree that is identical however
/// the input was ordered. Paths are parsed without touching the file system,
/// so Windows, POSIX, and UNC paths behave the same on every platform,
/// including the web. On top of the tree, the library provides the visible
/// rows of a tree view, search queries, selection with tri-state
/// checkboxes, diffs for animated lists, and text rendering.
///
/// ## Quick start
///
/// ```dart
/// import 'package:directory_tree/directory_tree.dart';
///
/// void main() {
///   final tree = DirectoryTree.fromPaths([
///     '/repo/lib/src/tree.dart',
///     '/repo/lib/main.dart',
///     '/repo/test/tree_test.dart',
///     '/repo/README.md',
///   ]);
///   print(tree.render());
///   // repo/
///   // ├── lib/
///   // │   ├── src/
///   // │   │   └── tree.dart
///   // │   └── main.dart
///   // ├── test/
///   // │   └── tree_test.dart
///   // └── README.md
///
///   var rows = tree.flatten(expansion: const ExpansionState.collapsed());
///   rows = rows.toggleNode(rows.first.id); // the user opened "repo"
///   print(rows.map((row) => row.label)); // (repo, lib, test, README.md)
/// }
/// ```
///
/// ## Building blocks
///
/// * [TreePath] and [PathPolicy]: canonical paths and the rules for parsing
///   them (separators, case sensitivity, Unicode normalization).
/// * [TreeEntry]: one input path with its kind and optional data.
/// * [DirectoryTree]: the immutable tree, stored in pre-order with O(1)
///   lookup by [NodeId] and O(1) subtree ranges. Build it with
///   [DirectoryTree.build] or incrementally with a [DirectoryTreeBuilder].
/// * [TreeOptions]: which nodes are top level ([TreeRoots]) and how
///   siblings are ordered ([TreeOrder]).
/// * [TreeIssue]: inputs that were skipped, reported instead of thrown.
/// * [ExpansionState], [TreeRows], and [TreeRow]: the visible rows of a tree
///   for virtualized views, with incremental expand and collapse.
/// * [TreeFilter] and [TreeQuery]: node predicates and search-box queries
///   for filtered views.
/// * [SelectionState]: single or multiple selection with range selection
///   and tri-state checkbox semantics ([CheckState]).
/// * [ListDiff] and [TreeDiff]: minimal row diffs for animated lists and
///   added, removed, and changed nodes between two trees.
/// * [TreeStyle]: box-drawing styles for [DirectoryTree.render].
///
/// To build a tree from a directory on disk, also import
/// `package:directory_tree/io.dart`. It needs `dart:io`, so it is not
/// available on the web; this library never imports it.
library;

// Imported only so the references in the library documentation resolve.
import 'package:directory_tree/src/diff/list_diff.dart';
import 'package:directory_tree/src/diff/tree_diff.dart';
import 'package:directory_tree/src/filter/tree_filter.dart';
import 'package:directory_tree/src/filter/tree_query.dart';
import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/path/tree_path.dart';
import 'package:directory_tree/src/selection/selection_state.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:directory_tree/src/tree/tree_entry.dart';
import 'package:directory_tree/src/tree/tree_issue.dart';
import 'package:directory_tree/src/tree/tree_options.dart';
import 'package:directory_tree/src/view/expansion_state.dart';
import 'package:directory_tree/src/view/tree_renderer.dart';
import 'package:directory_tree/src/view/tree_rows.dart';

export 'package:directory_tree/src/diff/list_diff.dart';
export 'package:directory_tree/src/diff/tree_diff.dart';
export 'package:directory_tree/src/filter/tree_filter.dart';
export 'package:directory_tree/src/filter/tree_query.dart';
export 'package:directory_tree/src/path/path_policy.dart';
export 'package:directory_tree/src/path/tree_path.dart' show TreePath;
export 'package:directory_tree/src/selection/selection_state.dart';
export 'package:directory_tree/src/tree/directory_tree.dart';
export 'package:directory_tree/src/tree/node_id.dart';
export 'package:directory_tree/src/tree/tree_entry.dart';
export 'package:directory_tree/src/tree/tree_issue.dart';
export 'package:directory_tree/src/tree/tree_options.dart'
    show NodeComparator, TreeOptions, TreeOrder, TreeRoots;
export 'package:directory_tree/src/view/expansion_state.dart';
export 'package:directory_tree/src/view/tree_renderer.dart' show TreeStyle;
export 'package:directory_tree/src/view/tree_rows.dart' show TreeRow, TreeRows;
