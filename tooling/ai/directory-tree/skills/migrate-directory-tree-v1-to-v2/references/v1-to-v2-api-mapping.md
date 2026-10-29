# directory_tree 1.x to 2.0.0 API mapping

Every public declaration of directory_tree 1.0.0 and its 2.0.0
replacement, taken from the package's MIGRATION.md. "Removed" names the
alternative. Only the three rows marked `dart fix` are automated.

## TreeBuilder

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

## TreeData

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `TreeData` | `DirectoryTree<T>` | Immutable. `T` is the type of entry data. |
| `TreeData(...)` | Removed | Trees come only from `DirectoryTree.build`, `DirectoryTree.fromPaths`, `DirectoryTree.empty`, or a `DirectoryTreeBuilder`. |
| `TreeData.nodes` (`Map<String, TreeNode>`) | `tree.nodes` (a `List` in pre-order) and `tree[id]` | Look up a node by id with `tree[id]` or by path with `tree.nodeAt(path)`. |
| `TreeData.rootId` | Removed | There is no synthetic root. |
| `TreeData.visibleRootId` | `tree.roots`, `tree.rootNodes` | A tree can have several top-level nodes. |
| `TreeData.omitContainerRowAtRoot` | `flatten(showRoots: false)` | |

## TreeEntry

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `TreeEntry(id: ..., name: ..., fullPath: ..., isVirtual: ..., metadata: ...)` | `TreeEntry.file(path, data: ...)`, `TreeEntry.directory(path, data: ...)` | `TreeEntry<T>` is generic over its data. |
| `TreeEntry.id` | Removed | A node's identity is its path. Keep your own id in `data` if you need it. |
| `TreeEntry.name` | Removed | The name is the last path segment: `node.name`. |
| `TreeEntry.fullPath` | `TreeEntry.path` | The raw path, exactly as given. `dart fix` renames reads. |
| `TreeEntry.isVirtual` | Removed | There are no virtual entries; give every entry a path. |
| `TreeEntry.metadata` | `TreeEntry.data` | Typed as `T` instead of `Map<String, Object?>`. Read it from a node with `node.data`. |
| `TreeEntry.extension` | `node.path.extension` | Keeps its case; call `toLowerCase()` for the 1.x result. A name ending with `.` has the extension `''` instead of `'.'`. |

## TreeNode, NodeType, and SelectionOrigin

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

## Flattening and rows

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

## Diffing

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `diffVisibleNodes(before, after)` | `ListDiff.compute(before, after, keyOf: (row) => row.id)` | Works for any keyed list. Throws an `ArgumentError` when a key repeats within one list. |
| `ListDiff(removeIndicesDesc: ..., insertIndicesAsc: ...)` | Removed | Diffs come only from `ListDiff.compute`. |
| `ListDiff.removeIndicesDesc` | `ListDiff.removedIndices` | Same order (descending). `dart fix` renames reads. The list is now unmodifiable. |
| `ListDiff.insertIndicesAsc` | `ListDiff.insertedIndices` | Same order (ascending). `dart fix` renames reads. The list is now unmodifiable. |
| `ListDiff.isNoop` | `diff.removedIndices.isEmpty && diff.insertedIndices.isEmpty` | `ListDiff.isEmpty` also requires `changedIndices` to be empty, a list that 1.x did not have. |

## Paths, search, and reveal

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `basename(path)` | `TreePath.parse(path).name`, `TreeNode.name` | Or `basename` from `package:path`, which 2.0.0 no longer depends on. |
| `extensionLower(path)` | `TreePath.parse(path).extension.toLowerCase()` | See `TreeEntry.extension` above. |
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

## Expansion

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

## Selection

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

## New in 2.0.0

These have no 1.x counterpart: `TreePath` and `PathPolicy` (path parsing),
`TreeRoots` (top-level node strategies), `TreeIssue` (skipped input),
`TreeDiff` (added, removed, and changed nodes between two trees),
`DirectoryTree.render` and `TreeStyle` (text output), `TreeRows` navigation
helpers, JSON round trips for `ExpansionState` and `SelectionState`, and
`DirectoryScanner` in `package:directory_tree/io.dart` for reading a
directory from disk.
