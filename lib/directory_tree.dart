/// Deterministic, immutable directory trees for pure Dart.
///
/// Feed a list of paths (from a file picker, `git ls-files`, a server
/// response, or a scanner) and get an indexed tree that is identical however
/// the input was ordered. Paths are parsed without touching the file system,
/// so Windows, POSIX, and UNC paths behave the same on every platform,
/// including the web.
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
///     '/repo/README.md',
///   ]);
///
///   for (final node in tree.nodes) {
///     print('${'  ' * node.depth}${node.label}');
///   }
///   // repo
///   //   lib
///   //     src
///   //       tree.dart
///   //     main.dart
///   //   README.md
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
/// * [TreeFilter]: node predicates for filtered views.
library;

// Imported only so the references in the library documentation resolve.
import 'package:directory_tree/src/filter/tree_filter.dart';
import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/path/tree_path.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:directory_tree/src/tree/tree_entry.dart';
import 'package:directory_tree/src/tree/tree_issue.dart';
import 'package:directory_tree/src/tree/tree_options.dart';

export 'package:directory_tree/src/filter/tree_filter.dart';
export 'package:directory_tree/src/path/path_policy.dart';
export 'package:directory_tree/src/path/tree_path.dart' show TreePath;
export 'package:directory_tree/src/tree/directory_tree.dart';
export 'package:directory_tree/src/tree/node_id.dart';
export 'package:directory_tree/src/tree/tree_entry.dart';
export 'package:directory_tree/src/tree/tree_issue.dart';
export 'package:directory_tree/src/tree/tree_options.dart'
    show NodeComparator, TreeOptions, TreeOrder, TreeRoots;
