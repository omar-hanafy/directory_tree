# Migrating from directory_tree 1.x to 2.0.0

2.0.0 is a rewrite. 1.x kept the tree as a mutable map of string ids, added
synthetic `root` and `tree_root` nodes, supported virtual entries, and was
configured through sixteen named arguments of `TreeBuilder.build`. Its
expansion and selection helpers were mutable sets.

2.0.0 replaces that model with an immutable, indexed `DirectoryTree`:

- Nodes are stored in pre-order, with O(1) lookup by id and O(1) subtree
  ranges.
- A node's id is its canonical path (`NodeId`), so ids are readable and stay
  stable across rebuilds.
- Input order never changes the result, and bad input is reported in
  `DirectoryTree.issues` instead of being dropped silently.
- Expansion, selection, filters, and diffs are immutable values.
- The core library depends only on `package:meta` and runs on every
  platform, including the web and dart2wasm.

What stayed the same, in concept:

- You pass a flat list of paths and get a deterministic tree.
- You flatten the tree into visible rows for a list view.
- Rows are diffed with a longest increasing subsequence (LIS), so an
  animated list removes and inserts as few rows as possible.
- A search filter keeps the ancestors of every match visible.
- Expansion and selection state are keyed by node ids that survive rebuilds.

Almost every public name changed or changed shape, so plan to touch every
file that imports `package:directory_tree`.

## dart fix

`dart fix --apply` migrates only three member renames whose meaning and type
did not change:

| 1.x | 2.0.0 |
| --- | --- |
| `ListDiff.removeIndicesDesc` | `ListDiff.removedIndices` |
| `ListDiff.insertIndicesAsc` | `ListDiff.insertedIndices` |
| `TreeEntry.fullPath` | `TreeEntry.path` |

Everything else needs a manual change. A rename would not help, because the
replacement types have a different shape: mutable sets became immutable
values, string ids became `NodeId`s, and many classes were merged or removed.
For example, renaming `ExpansionSet` to `ExpansionState` would still compile
for `expansion.toggle(id)`, but the call would discard the new state and
change nothing. An automatic rename like that would hide bugs.

These transforms were verified with Dart 3.13.5 against code written for
1.0.0.

`dart fix` can only rename a getter on a variable whose type it can resolve.
In `diffVisibleNodes(a, b).removeIndicesDesc` it cannot, because
`diffVisibleNodes` no longer exists. Replace the removed calls by hand, then
run `dart fix --apply` again to pick up the remaining renames.

## API mapping

Every public declaration of 1.0.0 (everything `package:directory_tree/directory_tree.dart`
exported) and its 2.0.0 replacement. "Removed" names the alternative.

### TreeBuilder

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `TreeBuilder` | `DirectoryTree.build`, `DirectoryTree.fromPaths`, `DirectoryTreeBuilder` | `DirectoryTreeBuilder` collects entries incrementally (`addFile`, `addDirectory`, `remove`) and builds snapshots. |
| `TreeBuilder()` | `DirectoryTreeBuilder(options: ..., entries: ...)` | |
| `TreeBuilder.build(entries: ...)` | `DirectoryTree.build(entries, options: ...)` | Returns a `DirectoryTree`. Options live in one `TreeOptions` value. |
| `TreeBuilder.rootId` (`'root'`) | Removed | There is no synthetic root. Use `tree.roots` or `tree.rootNodes`. |
| `TreeBuilder.treeRootId` (`'tree_root'`) | Removed | There is no container node. Use `tree.roots` or `tree.rootNodes`. |
| `build(sourceRoots: ...)` | `TreeEntry.directory(root)` entries | A directory entry becomes a top-level node unless another entry contains it, as a 1.x source root did. Use `TreeRoots.fixed(roots)` to show only those roots. |
| `build(selectedDirectories: ...)` | `TreeEntry.directory(path)` entries | Directory entries stay in the tree even when empty, and `node.isExplicit` is true for them. |
| `build(rootFolderLabel: ...)` | Removed | There is no container row to label. |
| `build(expandFoldersByDefault: ...)` | `ExpansionState.expanded()` or `ExpansionState.collapsed()` | Pass the state to `flatten` or `render`. |
| `build(selectNewFilesByDefault: ...)` | Removed | Build the state yourself: `SelectionState(mode: SelectionMode.multiple, selected: tree.files.map((node) => node.id))`. |
| `build(preferDeepestRoot: ...)` | Removed | The flag had no effect in 1.0.0. |
| `build(sortChildrenByName: ...)` | `TreeOptions(order: ...)` | Siblings are always sorted. There is no input-order mode, because the result never depends on input order. |
| `build(stripPrefixes: ...)` | Removed | Display relative paths with `node.path.relativeTo(TreePath.parse(prefix))`, or build the tree from relative paths. |
| `build(autoPickVisibleRoot: ...)`, `build(visibleRootMaxHoistLevels: ...)`, `build(visibleRootIgnoreVirtualFiles: ...)` | Removed | The top-level nodes come from `TreeOptions.roots`. To show a chain of single folders on one row, use `flatten(compactFolders: true)`. |
| `build(mergeVirtualIntoRealFolders: ...)` | Removed | There are no virtual entries. |
| `build(caseInsensitivePaths: ...)` | `TreeOptions(paths: PathPolicy.caseInsensitive)` | The default changed: 2.0.0 is case sensitive. |
| `build(unicodeNormalize: ...)` | `TreeOptions(paths: PathPolicy(unicodeNormalizer: ...))` | |
| `build(autoComputeAnchors: true)` | `TreeOptions(roots: TreeRoots.minimal())` | The default in both versions. |
| `build(autoComputeAnchors: false)` | `TreeOptions(roots: TreeRoots.fixed(roots))` | 1.x dropped files outside the source roots silently; 2.0.0 reports them as `TreeIssueKind.outsideRoots`. |
| `build(omitContainerRowAtRoot: ...)` | `flatten(showRoots: false)`, `render(showRoots: false)` | |

### TreeData

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `TreeData` | `DirectoryTree<T>` | Immutable. `T` is the type of entry data. |
| `TreeData(...)` | Removed | Trees come only from `DirectoryTree.build`, `DirectoryTree.fromPaths`, `DirectoryTree.empty`, or a `DirectoryTreeBuilder`. |
| `TreeData.nodes` (`Map<String, TreeNode>`) | `tree.nodes` (a `List` in pre-order) and `tree[id]` | Look up a node by id with `tree[id]` or by path with `tree.nodeAt(path)`. |
| `TreeData.rootId` | Removed | There is no synthetic root. |
| `TreeData.visibleRootId` | `tree.roots`, `tree.rootNodes` | A tree can have several top-level nodes. |
| `TreeData.omitContainerRowAtRoot` | `flatten(showRoots: false)` | |

### TreeEntry

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `TreeEntry(id: ..., name: ..., fullPath: ..., isVirtual: ..., metadata: ...)` | `TreeEntry.file(path, data: ...)`, `TreeEntry.directory(path, data: ...)` | `TreeEntry<T>` is generic over its data. |
| `TreeEntry.id` | Removed | A node's identity is its path. Keep your own id in `data` if you need it. |
| `TreeEntry.name` | Removed | The name is the last path segment: `node.name`. |
| `TreeEntry.fullPath` | `TreeEntry.path` | The raw path, exactly as given. `dart fix` renames reads. |
| `TreeEntry.isVirtual` | Removed | There are no virtual entries; give every entry a path. |
| `TreeEntry.metadata` | `TreeEntry.data` | Typed as `T` instead of `Map<String, Object?>`. Read it from a node with `node.data`. |
| `TreeEntry.extension` | `node.path.extension` | Keeps its case; call `toLowerCase()` for the 1.x result. A name ending with `.` has the extension `''` instead of `'.'`. |

### TreeNode, NodeType, and SelectionOrigin

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `TreeNode` | `TreeNode<T>`, a sealed class: `FileNode<T>` or `DirectoryNode<T>` | Created only by the builder. A `switch` over a node is exhaustive. |
| `TreeNode(...)` | Removed | |
| `TreeNode.id` (`String`) | `TreeNode.id` (`NodeId`) | `id.value` is the string. `NodeId(saved)` restores a stored id. |
| `TreeNode.name` | `TreeNode.name`, `TreeNode.label` | `name` is the last path segment. `label` is the text to display; it differs from `name` only for top-level nodes whose names collide. |
| `TreeNode.type` | `TreeNode.kind` (`TreeNodeKind`), `isFile`, `isDirectory` | |
| `TreeNode.parentId` (`''` for the root) | `TreeNode.parent` (`NodeId?`), `tree.parentOf(id)` | `null` for top-level nodes. |
| `TreeNode.childIds` | `DirectoryNode.children`, `tree.childrenOf(id)` | Only directories have children. |
| `TreeNode.sourcePath` | `TreeNode.path.toString()`, `TreeNode.entry?.path` | The canonical path, or the raw path of the entry. |
| `TreeNode.virtualPath` | `TreeNode.path` (`TreePath`) | A real path, without the 1.x `/tree` prefix. |
| `TreeNode.entryId` | `TreeNode.entry`, `TreeNode.data` | The node holds its entry directly. |
| `TreeNode.isVirtual` | Removed | |
| `TreeNode.isExpanded` | `ExpansionState.isExpanded(id)`, `TreeRow.isExpanded` | Nodes carry no view state. |
| `TreeNode.isSelected` | `SelectionState.isSelected(id)` | Nodes carry no view state. |
| `TreeNode.origin` | `TreeNode.isExplicit` | True when an entry produced the node, false for inferred directories. |
| `TreeNode.copyWith(...)` | Removed | Derive a new tree with `tree.rebuild(...)`. |
| `TreeNode.props` and `==` (by id only) | `==` by value | Two nodes are equal when their id, path, label, parent, depth, entry, and children are equal. |
| `NodeType` | `TreeNodeKind` | |
| `NodeType.root` | Removed | There is no synthetic root. `node.isRoot` is true for top-level nodes. |
| `NodeType.folder` | `TreeNodeKind.directory` | |
| `NodeType.file` | `TreeNodeKind.file` | |
| `SelectionOrigin` | `TreeNode.isExplicit` | |
| `SelectionOrigin.direct` | `isExplicit == true` | |
| `SelectionOrigin.inferred` | `isExplicit == false` | |
| `SelectionOrigin.none` | Removed | 1.x used it for files. A file node always has an entry, so `isExplicit` is true. |

### Flattening and rows

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `FlattenStrategy` | `DirectoryTree.flatten` | One flattening, configured by arguments. Filtering moved to `TreeFilter`, ordering to `TreeOptions.order`. |
| `FlattenStrategy.flatten(data: ..., expandedIds: ..., filterQuery: ...)` | `tree.flatten(expansion: ..., filter: ...)` | Returns `TreeRows<T>`, an unmodifiable `List<TreeRow<T>>` with incremental `expandNode`, `collapseNode`, `toggleNode`, and `reveal`. |
| `DefaultFlattenStrategy` | `tree.flatten()` | |
| `SortedFlattenStrategy(delegate)` | `TreeOptions(order: ...)` | The order is applied when the tree is built, so every view shares it. |
| `SortedFlattenStrategy.delegate` | `tree.options.order` | |
| `SortDelegate` | `NodeComparator` | `int Function(TreeNode<Object?> a, TreeNode<Object?> b)`. Wrap a typed comparator with `TreeOrder.by<T>`. Ties are broken by id. |
| `SortDelegate.sortChildIds(data, parentId)` | Removed | `DirectoryNode.children` is already in order. |
| `AlphaSortDelegate` | `TreeOrder.directoriesFirst` | The default order. It now compares names in natural order; see behavior changes. `TreeOrder.alphabetical` mixes files and directories. |
| `VisibleNode` | `TreeRow<T>` | |
| `VisibleNode(...)` | Removed | Rows come only from `flatten`. |
| `VisibleNode.id` (`String`) | `TreeRow.id` (`NodeId`) | |
| `VisibleNode.depth` | `TreeRow.depth` | |
| `VisibleNode.name` | `TreeRow.label`, `TreeRow.node.name` | `label` joins the names of a compacted row (`lib/src`). |
| `VisibleNode.type` | `TreeRow.node.kind` | |
| `VisibleNode.hasChildren` | `TreeRow.hasChildren` | Now false when a filter hides every child. |
| `VisibleNode.virtualPath` | `TreeRow.node.path` | |
| `VisibleNode.entryId` | `TreeRow.node.entry` | |
| `VisibleNode.isVirtual` | Removed | |
| `VisibleNode.sourcePath` | `TreeRow.node.path`, `TreeRow.node.entry?.path` | |
| `VisibleNode.origin` | `TreeRow.node.isExplicit` | |

### Diffing

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `diffVisibleNodes(before, after)` | `ListDiff.compute(before, after, keyOf: (row) => row.id)` | Works for any keyed list. Keys must be unique within each list: a repeat in the part that differs throws an `ArgumentError`, and repeats elsewhere are caught only with assertions enabled. |
| `ListDiff(removeIndicesDesc: ..., insertIndicesAsc: ...)` | Removed | Diffs come only from `ListDiff.compute`. |
| `ListDiff.removeIndicesDesc` | `ListDiff.removedIndices` | Same order (descending). `dart fix` renames reads. The list is now unmodifiable. |
| `ListDiff.insertIndicesAsc` | `ListDiff.insertedIndices` | Same order (ascending). `dart fix` renames reads. The list is now unmodifiable. |
| `ListDiff.isNoop` | `diff.removedIndices.isEmpty && diff.insertedIndices.isEmpty` | `ListDiff.isEmpty` also requires `changedIndices` to be empty, a list that 1.x did not have. |

### Paths, search, and reveal

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `basename(path)` | `TreePath.parse(path).name`, `TreeNode.name` | Or `basename` from `package:path`, which 2.0.0 no longer depends on. `TreePath.parse` throws a `FormatException` for inputs 1.x accepted, such as `''` and a relative `'..'`; use `TreePath.tryParse` (null instead) for input that may not be a path. `'a/..'` resolves to `.`, so its name is `.`, where 1.x returned `..`. |
| `extensionLower(path)` | `TreePath.parse(path).extension.toLowerCase()` | See `TreeEntry.extension` above, and the `basename` row for inputs that do not parse. |
| `hasAnyExtension(name, extensions)` | `TreeQuery.parse('ext:jpg,png')` | For a single name, compare `TreePath.parse(name).extension.toLowerCase()` yourself. |
| `ancestorChain(data, nodeId)` | `tree.ancestorsOf(id)` | Nearest ancestor first and without the node itself; 1.x started at the synthetic root and ended with the node. To show a node, use `ExpansionState.reveal(tree, id)` or `TreeRows.reveal(id)`. |
| `findByVirtualPath(data, virtualPath)` | `tree.nodeAt(path)`, `tree.idOf(path)` | Takes the real path, parsed with the tree's `PathPolicy`. O(1) instead of a scan. |
| `Predicate` | `TreeFilter` | Build one from a function with `TreeFilter.where`. Combine with `and`, `or`, `negate`. |
| `compileFilter(query)` | `TreeQuery.parse(query)` | A `TreeFilter`. `matches(node)` replaces calling the predicate. See behavior changes for syntax. |
| `FolderSelection` | `CheckState` | |
| `FolderSelection.none` | `CheckState.unchecked` | |
| `FolderSelection.partial` | `CheckState.partial` | |
| `FolderSelection.all` | `CheckState.checked` | |
| `folderSelection(data: ..., selectedIds: ..., folderId: ...)` | `selection.checkStateOf(tree, id)` | `selection.checkStates(tree)` computes every node in one pass. |

### Expansion

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `ExpansionSet` | `ExpansionState` | Immutable. Every method returns a new state; keep the result. |
| `ExpansionSet()` | `ExpansionState.collapsed()` | |
| `ExpansionSet(initiallyExpanded: ids)` | `ExpansionState.withExpanded(ids)` | Ids are `NodeId`s. |
| `ExpansionSet.isExpanded(id)` | `ExpansionState.isExpanded(id)` | |
| `ExpansionSet.setExpanded(id, expanded)` | `ExpansionState.setExpanded(id, expanded: expanded)` | Returns the new state instead of a `bool`. `identical(next, state)` tells whether anything changed. |
| `ExpansionSet.toggle(id)` | `ExpansionState.toggle(id)` | |
| `ExpansionSet.expandAll(ids)` | `ExpansionState.expandAll(ids)` | |
| `ExpansionSet.collapseAll()` | `const ExpansionState.collapsed()` | `ExpansionState.collapseAll(ids)` exists but collapses only the given ids. |
| `ExpansionSet.retainWhere(test)` | `ExpansionState.prune(tree)` | `prune` drops ids that are not directories of the tree. For any other test, build `ExpansionState.withExpanded(state.exceptions.where(test))`. |
| `ExpansionSet.expandedIds` | `ExpansionState.exceptions` | In a collapsed-by-default state the exceptions are the expanded ids. `toJson()` gives a stable form to store. |

### Selection

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `SelectionMode` | `SelectionMode` | |
| `SelectionMode.single` | `SelectionMode.single` | |
| `SelectionMode.multi` | `SelectionMode.multiple` | |
| `SelectionSet` | `SelectionState` | Immutable. Every method returns a new state; keep the result. |
| `SelectionSet(mode: mode)` | `SelectionState.empty(mode: mode)` | |
| `SelectionSet.mode` (settable) | `SelectionState.mode`, `withMode(mode)` | |
| `SelectionSet.isSelected(id)` | `SelectionState.isSelected(id)` | |
| `SelectionSet.selectedIds` | `SelectionState.selected` | |
| `SelectionSet.selectOnly(id)` | `SelectionState.select(id)` | Also sets the range anchor. |
| `SelectionSet.toggle(id)` | `SelectionState.toggle(id)` | In single mode, toggling the selected id now clears it. |
| `SelectionSet.clear()` | `SelectionState.clear()` | Also clears the anchor. |
| `SelectionSet.selectRange(order, anchorId, toId)` | `SelectionState.extendTo(toId, order)` | The anchor is part of the state; `select` and `toggle` set it, and `withAnchor(id)` sets it directly. |
| `SelectionSet.addAll(ids)` | `SelectionState.addAll(ids)` | In single mode only the last id is kept. |
| `SelectionSet.removeAll(ids)` | `SelectionState.removeAll(ids)` | |
| `SelectionSet.retainWhere(test)` | `SelectionState.prune(tree)` | `prune` drops ids the tree does not contain. For any other test, use `removeAll(state.selected.where((id) => !test(id)))`. |

### New in 2.0.0

These have no 1.x counterpart: `TreePath` and `PathPolicy` (path parsing),
`TreeRoots` (top-level node strategies), `TreeIssue` (skipped input),
`TreeDiff` (added, removed, and changed nodes between two trees),
`DirectoryTree.render` and `TreeStyle` (text output), `TreeRows` navigation
helpers, JSON round trips for `ExpansionState` and `SelectionState`, and
`DirectoryScanner` in `package:directory_tree/io.dart` for reading a
directory from disk.

## Before and after

Each pair shows the 1.x code first, then the 2.0.0 code. The examples share
one tree, built in the first pair.

### Build a tree from paths

```dart
// directory_tree 1.x
final tree = TreeBuilder().build(
  entries: const [
    TreeEntry(id: 'main', name: 'main.dart', fullPath: '/repo/lib/main.dart'),
    TreeEntry(
      id: 'tree',
      name: 'tree.dart',
      fullPath: '/repo/lib/src/tree.dart',
    ),
    TreeEntry(id: 'readme', name: 'README.md', fullPath: '/repo/README.md'),
  ],
);
final repo = tree.nodes[tree.visibleRootId]!;
print(repo.name); // repo
print(repo.childIds.map((id) => tree.nodes[id]!.name)); // (lib, README.md)
final main = tree.nodes.values.firstWhere((node) => node.entryId == 'main');
print(main.id); // node_main
```

```dart
final tree = DirectoryTree.fromPaths([
  '/repo/lib/main.dart',
  '/repo/lib/src/tree.dart',
  '/repo/README.md',
]);
final repo = tree.rootNodes.single;
final children = tree.childrenOf(repo.id);
print(repo.name); // repo
print(children.map((node) => node.name)); // (lib, README.md)
print(tree.nodeAt('/repo/lib/main.dart')!.id); // /repo/lib/main.dart
```

`fromPaths` makes a file entry for each path and a directory entry for a
path that ends with `/`. To find a node, use its path instead of scanning
the nodes.

### Attach data to entries

```dart
// directory_tree 1.x
const entries = [
  TreeEntry(
    id: 'main',
    name: 'main.dart',
    fullPath: '/repo/lib/main.dart',
    metadata: {'size': 1024},
  ),
];
final sized = TreeBuilder().build(
  entries: entries,
  selectedDirectories: const ['/repo/assets'],
);
final node = sized.nodes.values.firstWhere((n) => n.entryId == 'main');
final entry = entries.firstWhere((e) => e.id == node.entryId);
print(entry.metadata!['size']); // 1024
```

```dart
final sized = DirectoryTree<int>.build([
  TreeEntry.file('/repo/lib/main.dart', data: 1024),
  TreeEntry.directory('/repo/assets'),
]);
print(sized.nodeAt('/repo/lib/main.dart')!.data); // 1024
print(sized.nodeAt('/repo/assets')!.isExplicit); // true
```

The node keeps its entry, so there is no lookup table from entry ids to
entries.

### Visible rows for a list view

```dart
// directory_tree 1.x
const strategy = DefaultFlattenStrategy();
final none = ExpansionSet().expandedIds;
final top = strategy.flatten(data: tree, expandedIds: none);
print(top.map((row) => row.name)); // (repo)
final everything = tree.nodes.keys.toSet();
final rows = strategy.flatten(data: tree, expandedIds: everything);
final names = rows.map((row) => row.name);
print(names); // (repo, lib, src, tree.dart, main.dart, README.md)
print(rows.map((row) => row.depth)); // (0, 1, 2, 3, 2, 1)
```

```dart
final top = tree.flatten(expansion: const ExpansionState.collapsed());
print(top.map((row) => row.label)); // (repo)
final rows = tree.flatten(); // every directory is expanded by default
final labels = rows.map((row) => row.label);
print(labels); // (repo, lib, src, tree.dart, main.dart, README.md)
print(rows.map((row) => row.depth)); // (0, 1, 2, 3, 2, 1)
```

`TreeRows` is a `List`, so it plugs into a virtualized list as
`itemCount: rows.length` and `itemBuilder: (context, i) => buildRow(rows[i])`.
Each row also has `isExpanded`, `hasChildren`, `isLast`, and `guides` for
drawing arrows and connector lines.

### Expand and collapse

```dart
// directory_tree 1.x
final libId = tree.nodes.values.firstWhere((node) => node.name == 'lib').id;
final expansion = ExpansionSet(initiallyExpanded: {tree.visibleRootId});
expansion.toggle(libId); // changes the set in place
final rows = const DefaultFlattenStrategy().flatten(
  data: tree,
  expandedIds: expansion.expandedIds,
);
print(rows.map((row) => row.name)); // (repo, lib, src, main.dart, README.md)
```

```dart
final lib = tree.idOf('/repo/lib')!;
var rows = tree.flatten(expansion: ExpansionState.withExpanded(tree.roots));
rows = rows.toggleNode(lib); // new rows; only the changed rows are built
print(rows.map((row) => row.label)); // (repo, lib, src, main.dart, README.md)
rows = rows.collapseNode(lib);
print(rows.map((row) => row.label)); // (repo, lib, README.md)

// Without rows, change the state itself. It is immutable: keep the result.
var expansion = const ExpansionState.collapsed();
expansion = expansion.expand(tree.roots.single).expand(lib);
print(expansion.isExpanded(lib)); // true
```

Store `rows.requestedExpansion` (for example with `toJson`) to restore the
view later. It leaves out the folders a search opened.

### Filter and search

```dart
// directory_tree 1.x
final matches = const DefaultFlattenStrategy().flatten(
  data: tree,
  expandedIds: const {},
  filterQuery: 'ext:dart !main',
);
print(matches.map((row) => row.name)); // (repo, lib, src, tree.dart)
```

```dart
final query = TreeQuery.parse('ext:dart !main');
final matches = tree.flatten(
  expansion: const ExpansionState.collapsed(),
  filter: query,
);
print(matches.map((row) => row.label)); // (repo, lib, src, tree.dart)
print(matches.map((row) => row.isMatch)); // (false, false, false, true)

// Combine a query with your own predicate.
final dotFiles = TreeFilter.where<Object?>((n) => n.name.startsWith('.'));
print(tree.flatten(filter: query.and(dotFiles.negate())).length); // 4
```

`isMatch` tells a match from an ancestor shown only for context, and
`query.matchRanges(row.label)` gives the ranges to highlight.

### Selection

```dart
// directory_tree 1.x
final ids = const DefaultFlattenStrategy()
    .flatten(data: tree, expandedIds: tree.nodes.keys.toSet())
    .map((row) => row.id)
    .toList();
final selection = SelectionSet(mode: SelectionMode.multi);
selection.toggle(ids[1]); // lib
selection.selectRange(ids, ids[1], ids[3]); // lib to tree.dart
print(selection.selectedIds.length); // 3
final state = folderSelection(
  data: tree,
  selectedIds: selection.selectedIds,
  folderId: ids[0], // repo
);
print(state); // FolderSelection.partial
```

```dart
final rows = tree.flatten();
final order = rows.map((row) => row.id);
final repo = tree.roots.single;
var selection = const SelectionState.empty(mode: SelectionMode.multiple);
selection = selection.toggle(rows[1].id); // lib; also sets the anchor
selection = selection.extendTo(rows[3].id, order); // to tree.dart
print(selection.length); // 3
print(selection.checkStateOf(tree, repo)); // CheckState.partial

// Checkboxes: check a folder to select every leaf below it.
final lib = tree.idOf('/repo/lib')!;
selection = selection.check(tree, lib);
print(selection.checkStateOf(tree, lib)); // CheckState.checked
```

### Diff visible rows for an animated list

```dart
// directory_tree 1.x
const strategy = DefaultFlattenStrategy();
final opened = {tree.visibleRootId};
final before = strategy.flatten(data: tree, expandedIds: opened);
final everything = tree.nodes.keys.toSet();
final after = strategy.flatten(data: tree, expandedIds: everything);
final diff = diffVisibleNodes(before, after);
print(diff.removeIndicesDesc); // []
print(diff.insertIndicesAsc); // [2, 3, 4]
```

```dart
final opened = ExpansionState.withExpanded(tree.roots);
final before = tree.flatten(expansion: opened);
final after = tree.flatten();
final diff = ListDiff.compute(before, after, keyOf: (row) => row.id);
print(diff.removedIndices); // []
print(diff.insertedIndices); // [2, 3, 4]
print(diff.changedIndices); // [1]
```

Apply `removedIndices` with `removeItem` and `insertedIndices` with
`insertItem`, as in 1.x. `changedIndices` is new: rows that kept their place
but changed, here the `lib` row, whose arrow now points down.

### Print a tree

```dart
// directory_tree 1.x
void printTree(TreeData tree, String id, [String indent = '']) {
  final node = tree.nodes[id]!;
  final slash = node.type == NodeType.folder ? '/' : '';
  print('$indent${node.name}$slash');
  for (final child in node.childIds) {
    printTree(tree, child, '$indent  ');
  }
}

printTree(tree, tree.visibleRootId);
// repo/
//   lib/
//     src/
//       tree.dart
//     main.dart
//   README.md
```

```dart
print(tree.render());
// repo/
// ├── lib/
// │   ├── src/
// │   │   └── tree.dart
// │   └── main.dart
// └── README.md
```

`render` takes the same `expansion`, `filter`, and `showRoots` arguments as
`flatten`, plus `style` (`TreeStyle.unicode`, `TreeStyle.ascii`,
`TreeStyle.indent`, or your own) and `maxDepth`.

### Source roots and empty directories

```dart
// directory_tree 1.x
final rooted = TreeBuilder().build(
  entries: const [
    TreeEntry(id: 'main', name: 'main.dart', fullPath: '/repo/lib/main.dart'),
  ],
  sourceRoots: const ['/repo'],
  selectedDirectories: const ['/repo/assets'],
);
print(rooted.nodes[rooted.visibleRootId]!.name); // repo
```

```dart
final rooted = DirectoryTree.fromPaths([
  '/repo/', // a directory entry, like a 1.x source root
  '/repo/lib/main.dart',
  '/repo/assets/', // kept although empty, like a 1.x selected directory
]);
print(rooted.render(style: TreeStyle.indent));
// repo/
//   assets/
//   lib/
//     main.dart
```

### Options: case, roots, and order

```dart
// directory_tree 1.x
final options = TreeBuilder().build(
  entries: const [
    TreeEntry(id: 'x', name: 'x.dart', fullPath: r'C:\Repo\b\x.dart'),
    TreeEntry(id: 'a', name: 'a.md', fullPath: r'c:\Repo\a.md'),
  ],
  sourceRoots: const [r'C:\Repo'],
  autoComputeAnchors: false, // only the source roots
  caseInsensitivePaths: true, // the 1.x default
);
print(options.nodes[options.visibleRootId]!.sourcePath); // C:/Repo
```

```dart
final options = DirectoryTree.fromPaths(
  [r'C:\Repo\b\x.dart', r'c:\Repo\a.md'],
  options: const TreeOptions(
    paths: PathPolicy.caseInsensitive,
    roots: TreeRoots.fixed([r'C:\Repo']),
    order: TreeOrder.alphabetical, // files and directories mixed
  ),
);
print(options.rootNodes.single.path); // C:/Repo
print(options.roots.single); // c:/repo
print(options.nodes.map((node) => node.name)); // (Repo, a.md, b, x.dart)
```

A custom 1.x `SortDelegate` becomes a comparator in `TreeOptions.order`.
`TreeOrder.by` adapts a comparator over typed nodes:

```dart
final bySize = TreeOrder.by<int>(
  (a, b) => (a.data ?? 0).compareTo(b.data ?? 0),
);
final sizes = DirectoryTree<int>.build([
  TreeEntry.file('/r/big.bin', data: 900),
  TreeEntry.file('/r/small.txt', data: 5),
], options: TreeOptions(order: bySize));
print(sizes.files.map((node) => node.name)); // (small.txt, big.bin)
```

### Reveal and find a node

```dart
// directory_tree 1.x
final found = findByVirtualPath(tree, '/tree/repo/lib/src/tree.dart')!;
final chain = ancestorChain(tree, found).map((id) => tree.nodes[id]!.name);
print(chain); // (Root, tree, repo, lib, src, tree.dart)
```

```dart
final found = tree.idOf('/repo/lib/src/tree.dart')!;
print(tree.ancestorsOf(found).map((node) => node.name)); // (src, lib, repo)
final rows = tree.flatten(expansion: const ExpansionState.collapsed());
print(rows.reveal(found).indexOfNode(found)); // 3
```

## Behavior changes

These differences can change what your code does without a compile error.

- **Paths are case sensitive by default.** 1.x defaulted to
  `caseInsensitivePaths: true`. In 2.0.0, `/Repo/a` and `/repo/a` are
  different nodes unless you pass
  `TreeOptions(paths: PathPolicy.caseInsensitive)`. (1.x could also build
  folders named `..` when the same directory appeared in two spellings;
  2.0.0 merges them into one node under the case-insensitive policy.)
- **Node ids are canonical paths.** A file id was `node_<TreeEntry.id>` and
  a folder id was an encoded string such as `folder_sr_repo_L3JlcG8`. A
  2.0.0 id is the canonical path (`/repo/lib`), lowercased under a
  case-insensitive policy. Ids you stored with 1.x, for example for
  expansion or selection, do not match any 2.0.0 node. Map them yourself or
  start with an empty state.
- **There is no synthetic root.** 1.x always added a `root` node and a
  `tree_root` folder (labelled `tree` by default). 1.x flattened from
  `visibleRootId`, which could be that `tree` folder when there were
  several top-level folders. 2.0.0 has a list of top-level nodes,
  `tree.roots`, each with `parent == null`, and shows them all as depth-0
  rows.
- **No hidden levels.** 1.x moved `visibleRootId` down by up to two levels
  of single folders (`autoPickVisibleRoot`). 2.0.0 always shows the
  top-level nodes chosen by `TreeOptions.roots`. Use
  `flatten(compactFolders: true)` to draw a chain of single folders on one
  row.
- **Virtual entries and `virtualParent` are gone.** 1.x placed an entry with
  `isVirtual: true` under the `tree` folder, or under the folders named by
  its `metadata['virtualParent']`. In 2.0.0 every entry has a path. Give a
  placeholder file the path it should appear at, and mark it in `data` if
  your UI treats it differently.
- **Names come from paths.** 1.x already named a file's node after the
  last segment of `fullPath`, but virtual entries were shown as
  `TreeEntry.name`, and `TreeEntry.extension` was read from `name`, which
  could differ from the path. 2.0.0 has no separate name: `TreeNode.name`
  and `node.path.extension` both come from the last path segment.
- **Duplicate entries: the later one wins.** 1.x kept the first entry for a
  path and silently dropped later entries with the same path or the same
  `TreeEntry.id`. 2.0.0 has no entry ids. Entries with the same path merge,
  the later entry wins, and it keeps the position of the first.
- **Path parsing is stricter and handles more forms.** Both versions accept
  `/` and `\`, uppercase drive letters, and resolve `..` in absolute paths.
  The differences:
  - 1.x trimmed whitespace around a path; 2.0.0 keeps it as part of the
    segments.
  - 1.x kept a leading `..` in a relative path (`../up/a.txt` became a
    folder `up`). 2.0.0 skips the entry and reports a
    `TreeIssueKind.invalidPath` issue.
  - 1.x dropped the server of a UNC path (`\\server\share\a.txt` became
    `/share`). 2.0.0 keeps the UNC root `//server/share/`.
  - Paths that cannot be parsed, such as an empty path, are skipped and
    listed in `tree.issues`. A file entry that another entry lies inside is
    reported as a `TreeIssueKind.conflict`.
- **Sibling order is natural.** Directories still come before files, but
  names compare in natural order: `file2` comes before `file10`, where 1.x
  compared lowercased strings and put `file10` first. Names that differ
  only in case are ordered by exact code units. 1.x kept input order when
  `sortChildrenByName` was false; 2.0.0 always sorts, so input order never
  matters.
- **Top-level label collisions read like paths.** When two top-level
  directories share a name, 1.x labelled them `a - src` and `b - src`;
  2.0.0 labels them `a/src` and `b/src` in `TreeNode.label`.
- **Filters keep the ancestors of matches, as before, with these
  differences:**
  - 1.x forced every branch with a match open and ignored `expandedIds` for
    it, so the user could not collapse it during a search. 2.0.0 adds the
    ancestors of matches to the expansion state (`expandMatches: true`, the
    default), so they can be collapsed. `expandMatches: false` uses your
    state as given.
  - In 1.x `ext:` also matched folders whose names had that extension. In
    2.0.0 directories never match `ext:`.
  - In 1.x every term was a literal substring. In 2.0.0 `*` and `?` are
    glob wildcards, a term with `/` matches against the path, and quotes,
    `type:`, and `path:` have meaning. Quote a term (`"a*b"`) to search for
    it literally.
  - `TreeRow.hasChildren` is false when the filter hides every child; 1.x
    reported whether the folder had any children at all.
- **Default expansion is "everything open".** 1.x had no default:
  `flatten` required `expandedIds`, and `ExpansionSet()` started empty, so
  only the top row showed. `flatten` and `render` in 2.0.0 default to
  `ExpansionState.expanded()`. Pass `const ExpansionState.collapsed()` for
  the 1.x starting point.
- **State classes are immutable.** `ExpansionSet` and `SelectionSet`
  changed in place and returned a `bool`. `ExpansionState` and
  `SelectionState` return a new value, and an operation that changes
  nothing returns the same instance. A call whose result you drop does
  nothing; the methods are marked `@useResult`, so the analyzer warns. The
  same applies to trees: nodes have no `copyWith`, and `TreeData.nodes`
  was a mutable map while `DirectoryTree.nodes` is unmodifiable.
- **Single selection mode toggles off.** In 1.x, `toggle` on the selected
  id in single mode kept it selected. In 2.0.0 it clears the selection.
- **Empty directories are leaves.** 1.x `folderSelection` counted only
  files, so an empty folder was always `FolderSelection.none`, and a
  folder whose files were all selected was `all` even with an empty
  subfolder. 2.0.0 check states count leaves, which are files and
  directories without children. An empty directory can be checked, and an
  unchecked empty subfolder makes its parent `CheckState.partial`.
- **Row diffs reject duplicate keys and report changes.**
  `ListDiff.compute` throws an `ArgumentError` when a key repeats within
  one list, where 1.x returned a diff silently. Release builds check only
  the part of the lists that differs; repeats in the shared start and end
  are caught when assertions are enabled. It also lists kept rows
  whose content changed in `changedIndices`, so `isEmpty` is stricter than
  1.x `isNoop`.
- **Minimum SDK and dependencies.** 1.0.0 required Dart `^3.10.4`. 2.0.0
  requires `^3.8.0`, so it supports older SDKs too. The `equatable`,
  `path`, and `uuid` dependencies are gone; 2.0.0 depends only on `meta`.

## Upgrade checklist

1. Change the constraint to `directory_tree: ^2.0.0` and run `dart pub get`
   (`flutter pub get` in a Flutter app).
2. Run `dart fix --apply` for the three renames listed under
   [dart fix](#dart-fix).
3. Replace `TreeEntry(...)` with `TreeEntry.file` and
   `TreeEntry.directory`, moving `metadata` into `data`, and
   `TreeBuilder().build(...)` with `DirectoryTree.build` and `TreeOptions`.
   Add `TreeEntry.directory` entries for former `sourceRoots` and
   `selectedDirectories`.
4. Decide on case sensitivity. Pass `PathPolicy.caseInsensitive` to keep
   the 1.x default.
5. Replace `FlattenStrategy.flatten` with `tree.flatten`, `VisibleNode`
   with `TreeRow`, and `compileFilter` with `TreeQuery.parse`.
6. Replace `ExpansionSet` with `ExpansionState` and `SelectionSet` with
   `SelectionState`, assigning the result of every call.
7. Replace `diffVisibleNodes` with `ListDiff.compute(before, after, keyOf:
   (row) => row.id)`, then run `dart fix --apply` again.
8. Drop persisted 1.x node ids, or map them to paths, since 2.0.0 ids are
   canonical paths.
9. Check the [behavior changes](#behavior-changes) that affect your app,
   then run your analyzer and tests.
