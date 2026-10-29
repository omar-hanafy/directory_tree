# Changelog

All notable changes to this project will be documented in this file.

## 2.0.0

2.0.0 is a rewrite with a new API, and code written for 1.x does not compile
against it. [MIGRATION.md](MIGRATION.md) maps every 1.x declaration to its
replacement and lists the behavior changes. `dart fix --apply` renames
`ListDiff.removeIndicesDesc`, `ListDiff.insertIndicesAsc`, and
`TreeEntry.fullPath`; every other change is manual.

### Breaking changes
- `TreeBuilder`, `TreeData`, and the mutable `TreeNode` map are replaced by
  an immutable, indexed `DirectoryTree<T>`. Build it with
  `DirectoryTree.build`, `DirectoryTree.fromPaths`, or `DirectoryTreeBuilder`,
  and configure it with `TreeOptions`.
- `TreeEntry` is now `TreeEntry.file(path, data: ...)` or
  `TreeEntry.directory(path, data: ...)`, and `metadata` is now typed
  `data`. Entry ids, names, `isVirtual`, virtual entries, and
  `virtualParent` are removed.
- Node ids are `NodeId`s holding the canonical path instead of generated
  `node_...` and `folder_...` strings. The synthetic `root` and `tree_root`
  nodes, visible-root hoisting, `NodeType`, and `SelectionOrigin` are
  removed. Nodes are a sealed `TreeNode` with `FileNode` and `DirectoryNode`.
- Paths are case sensitive by default. Use `PathPolicy.caseInsensitive` for
  the 1.x behavior.
- `FlattenStrategy`, `DefaultFlattenStrategy`, `SortedFlattenStrategy`,
  `SortDelegate`, `AlphaSortDelegate`, and `VisibleNode` are replaced by
  `DirectoryTree.flatten`, `TreeRows`, `TreeRow`, and `TreeOptions.order`.
  Siblings sort directories first, in natural order (`file2` before
  `file10`).
- `diffVisibleNodes` is replaced by `ListDiff.compute`, which diffs any
  keyed list and reports kept rows whose content changed in
  `changedIndices`. Keys must be unique: a repeat in the part of the lists
  that differs throws an `ArgumentError`, and repeats elsewhere are caught
  when assertions are enabled.
- `compileFilter` and `Predicate` are replaced by `TreeQuery` and
  `TreeFilter`. Queries add glob, path, quoted, `type:`, and `path:` terms,
  and `ext:` no longer matches directories.
- `ExpansionSet` and `SelectionSet` are replaced by the immutable
  `ExpansionState` and `SelectionState`. `SelectionMode.multi` is now
  `SelectionMode.multiple`, and toggling the selected id in single mode now
  clears it. `folderSelection` and `FolderSelection` are replaced by
  `SelectionState.checkStateOf` and `CheckState`, which count empty
  directories as leaves.
- `basename`, `extensionLower`, `hasAnyExtension`, `ancestorChain`, and
  `findByVirtualPath` are removed. Use `TreePath`, `DirectoryTree.ancestorsOf`,
  and `DirectoryTree.nodeAt`.
- Bad input is skipped and reported in `DirectoryTree.issues` instead of
  being normalized or dropped silently: unparseable paths, relative paths
  that climb above their root, files that other entries lie inside, and
  entries outside fixed roots. When two entries share a path, the later one
  wins.

### Added
- `TreePath` and `PathPolicy`: platform-independent parsing of POSIX,
  Windows drive, and UNC paths, with optional case folding and Unicode
  normalization. Case-insensitive ids, `TreeQuery`, and
  `TreeOrder.compareNames` fold case with the package's own Unicode simple
  case folding table (Unicode 18.0.0), so results are identical on the VM,
  JavaScript, and WebAssembly.
- `TreeRoots`: minimal, common-ancestor, fixed, and file-system strategies
  for choosing the top-level nodes.
- `TreeRows` updates rows incrementally with `expandNode`, `collapseNode`,
  `toggleNode`, and `reveal`, supports compact folders and hidden roots, and
  offers row lookup for keyboard navigation. `requestedExpansion` gives the
  state to persist without the folders a search opened.
- `TreeRow` carries `isExpanded`, `isLast`, `guides`, `isMatch`, and the
  `chain` of a compacted row.
- `DirectoryTree.render` and `TreeStyle` print a tree like the `tree`
  command, escaping control characters in names so each row stays on one
  line.
- `TreeDiff` lists the nodes added, removed, and changed between two trees.
- `ExpansionState` and `SelectionState` round-trip through JSON.
  `SelectionState` keeps a range anchor and adds tri-state checks (`check`,
  `uncheck`, `toggleCheck`, `canCheck`, `checkStates`).
- `TreeQuery.matchRanges` returns the ranges of a label to highlight.
- `package:directory_tree/io.dart` adds `DirectoryScanner`, which lists a
  directory on disk as entries. It needs `dart:io`; the core library does
  not import it.

### Compatibility
- The minimum Dart SDK is now 3.8.0 (1.0.0 required 3.10.4).
- The `equatable`, `path`, and `uuid` dependencies are removed. The package
  depends only on `meta`.

## [1.0.0] - 2026-01-02

### Initial Release
- Core `TreeBuilder` for normalizing paths and generating deterministic tree structures.
- `TreeData` and `TreeNode` immutable models.
- `FlattenStrategy` (DFS) and `SortedFlattenStrategy` for linearizing trees.
- `diffVisibleNodes` using Longest Increasing Subsequence (LIS) for efficient list updates.
- `ExpansionSet` and `SelectionSet` state helpers.
- `compileFilter` for flexible text and extension searching.
- Cross-platform path normalization (Windows/POSIX).
