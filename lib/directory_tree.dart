/// The core entry point for the `directory_tree` package.
///
/// Use this library to build, manage, and interact with virtual file system trees.
/// It provides a deterministic way to transform flat lists of files into
/// hierarchical structures, suitable for file explorers in Flutter or CLIs.
///
/// ### Core Behavior
///
/// *   **Construct:** Use [TreeBuilder] to normalize paths and group files into a
///     [TreeData] graph.
/// *   **Traverse:** Use [FlattenStrategy] (like [DefaultFlattenStrategy]) to
///     convert the graph into a linear list for rendering.
/// *   **Interact:** Manage UI state with [ExpansionSet] and [SelectionSet], and
///     compute UI updates with [diffVisibleNodes].
///
/// ### Key Components
///
/// *   [TreeEntry]: The raw input item (file/entity).
/// *   [TreeBuilder]: The engine that produces the tree.
/// *   [TreeData]: The immutable result holding the graph.
/// *   [TreeNode]: A single vertex in the graph.
library;

export 'src/builder/tree_builder.dart';
export 'src/models/tree_data.dart';
export 'src/models/tree_entry.dart';
export 'src/models/tree_node.dart';
export 'src/ops/flatten.dart';
export 'src/ops/list_diff.dart';
export 'src/ops/path_utils.dart';
export 'src/ops/reveal.dart';
export 'src/ops/search_filter.dart';
export 'src/ops/selection_utils.dart';
export 'src/ops/sort_delegate.dart';
export 'src/ops/visible_node.dart';
export 'src/state/expansion_state.dart';
export 'src/state/selection_state.dart';
