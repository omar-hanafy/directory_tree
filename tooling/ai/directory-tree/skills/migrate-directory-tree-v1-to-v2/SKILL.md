---
name: migrate-directory-tree-v1-to-v2
description: Use when upgrading a project from directory_tree 1.x to 2.0.0, or fixing analyzer errors after that bump - TreeBuilder/TreeData/FlattenStrategy/VisibleNode/ExpansionSet/SelectionSet/diffVisibleNodes/compileFilter/folderSelection no longer existing, the dart fix renames (removeIndicesDesc, insertIndicesAsc, TreeEntry.fullPath), string node ids becoming NodeId canonical paths, the removed synthetic root and tree_root nodes, case-sensitive paths by default, immutable expansion and selection state, flatten expanding everything by default, natural sibling order, the new search syntax, or tests whose output changed after the upgrade.
---

# Migrate directory_tree 1.x to 2.0.0

2.0.0 is a rewrite. `dart fix` handles only three renames; every other 1.x
call needs a manual change, because the replacement types have a different
shape (mutable sets became immutable values, string ids became `NodeId`s,
classes were merged or removed). Never "fix" a compile error by renaming a
1.x class to its 2.0.0 namesake: `expansion.toggle(id)` on an
`ExpansionState` compiles and silently does nothing unless the result is
assigned.

## Preconditions

1. Clean git working tree; migrate on a branch. Never reset user work
   without explicit confirmation.
2. Run the tests BEFORE migrating and record the baseline.
3. Confirm the version: `dart pub deps --style=compact | grep '^- directory_tree '`
   (`flutter pub deps` in a Flutter app). 2.0.0 requires Dart `^3.8.0`
   (1.0.0 required `^3.10.4`, so the SDK never blocks this upgrade) and
   depends only on `meta`; `equatable`, `path`, and `uuid` are no longer
   pulled in. If the project imports one of them without listing it, add
   it to the project's own dependencies.

## Ordered steps

1. Set `directory_tree: ^2.0.0`; run `dart pub get` (or `flutter pub get`).
2. Find every use:

   ```bash
   grep -rln "package:directory_tree" lib/ test/ bin/
   grep -rnE "TreeBuilder|TreeData|FlattenStrategy|SortDelegate|VisibleNode|ExpansionSet|SelectionSet|diffVisibleNodes|compileFilter|folderSelection|FolderSelection|findByVirtualPath|ancestorChain|NodeType|SelectionOrigin|visibleRootId|rootId|treeRootId" lib/ test/ bin/
   ```

3. Run `dart fix --dry-run`, then `dart fix --apply`. It rewrites only:

   | 1.x | 2.0.0 |
   |---|---|
   | `ListDiff.removeIndicesDesc` | `ListDiff.removedIndices` |
   | `ListDiff.insertIndicesAsc` | `ListDiff.insertedIndices` |
   | `TreeEntry.fullPath` | `TreeEntry.path` |

   `dart fix` can only rename a getter whose receiver type it resolves, so
   `diffVisibleNodes(a, b).removeIndicesDesc` stays until step 4 replaces
   `diffVisibleNodes`.
4. Replace the removed API by hand with the mapping below (complete table:
   [references/v1-to-v2-api-mapping.md](references/v1-to-v2-api-mapping.md)).
5. Run `dart fix --apply` again to pick up the renames that step 4 made
   resolvable, then `dart analyze` until clean.
6. Walk the behavior checklist, then run the tests and compare with the
   baseline.

## Core mapping

| 1.x | 2.0.0 |
|---|---|
| `TreeBuilder().build(entries: ...)` | `DirectoryTree.build(entries, options: TreeOptions(...))`, or `DirectoryTree.fromPaths(paths)` |
| `TreeEntry(id:, name:, fullPath:, metadata:)` | `TreeEntry.file(path, data: ...)` / `TreeEntry.directory(path, data: ...)`; `TreeEntry<T>` is generic; there is no `id`, `name`, or `isVirtual` |
| `build(sourceRoots: ...)`, `build(selectedDirectories: ...)` | `TreeEntry.directory(path)` entries; `TreeRoots.fixed(roots)` to show only those roots |
| `build(caseInsensitivePaths: true)` (the 1.x default) | `TreeOptions(paths: PathPolicy.caseInsensitive)` |
| `build(unicodeNormalize: ...)` | `TreeOptions(paths: PathPolicy(unicodeNormalizer: ...))` |
| `build(sortChildrenByName: ...)`, `SortDelegate`, `SortedFlattenStrategy` | `TreeOptions(order: ...)`; `TreeOrder.by<T>(...)` for typed comparators |
| `build(omitContainerRowAtRoot: ...)` | `flatten(showRoots: false)`, `render(showRoots: false)` |
| `build(expandFoldersByDefault: ...)` | `ExpansionState.expanded()` / `ExpansionState.collapsed()` passed to `flatten` |
| `TreeData`, `data.nodes[id]` | `DirectoryTree<T>`, `tree[id]`; `tree.nodes` is a pre-order `List` |
| `data.visibleRootId`, `TreeBuilder.rootId`, `treeRootId` | `tree.roots` / `tree.rootNodes` (no synthetic root) |
| `node.id` (`String`) | `node.id` (`NodeId`); `id.value` is the string |
| `node.type`, `NodeType.folder` | `node.kind`, `TreeNodeKind.directory`, `node.isDirectory` |
| `node.parentId`, `node.childIds` | `node.parent` (`NodeId?`), `tree.childrenOf(id)` |
| `node.origin`, `SelectionOrigin` | `node.isExplicit` |
| `node.isExpanded`, `node.isSelected` | `expansion.isExpanded(id)`, `selection.isSelected(id)` |
| `DefaultFlattenStrategy().flatten(data:, expandedIds:, filterQuery:)` | `tree.flatten(expansion: ..., filter: TreeQuery.parse(q))` |
| `VisibleNode` (`name`, `type`) | `TreeRow` (`label`, `node.kind`) |
| `ExpansionSet()` / `ExpansionSet(initiallyExpanded: ids)` | `const ExpansionState.collapsed()` / `ExpansionState.withExpanded(ids)` |
| `set.toggle(id)`, `set.setExpanded(id, b)` | `state = state.toggle(id)`, `state = state.setExpanded(id, expanded: b)` |
| `ExpansionSet.collapseAll()` | `const ExpansionState.collapsed()` |
| `ExpansionSet.retainWhere(test)` | `state.prune(tree)` |
| `SelectionSet(mode: SelectionMode.multi)` | `SelectionState.empty(mode: SelectionMode.multiple)` |
| `selectOnly(id)`, `selectRange(order, anchor, to)`, `selectedIds` | `select(id)`, `extendTo(to, order)` (anchor is in the state), `selected` |
| `folderSelection(data:, selectedIds:, folderId:)`, `FolderSelection.all/none` | `selection.checkStateOf(tree, id)`, `CheckState.checked/unchecked` |
| `diffVisibleNodes(before, after)` | `ListDiff.compute(before, after, keyOf: (row) => row.id)` |
| `ListDiff.isNoop` | `removedIndices.isEmpty && insertedIndices.isEmpty` |
| `compileFilter(q)`, `Predicate` | `TreeQuery.parse(q)`, `TreeFilter.where<Object?>(...)` |
| `findByVirtualPath(data, '/tree/...')` | `tree.nodeAt(realPath)` / `tree.idOf(realPath)` |
| `ancestorChain(data, id)` | `tree.ancestorsOf(id)` (nearest first, without the node) |
| `basename(p)`, `extensionLower(p)` | `TreePath.parse(p).name`, `TreePath.parse(p).extension.toLowerCase()` |

A typical rewrite of a 1.x build, expand, and diff flow:

```dart
final tree = DirectoryTree.fromPaths([
  r'C:\Repo\lib\main.dart',
  r'c:\repo\README.md',
], options: const TreeOptions(paths: PathPolicy.caseInsensitive));
print(tree.roots.single.value); // c:/repo
var expansion = const ExpansionState.collapsed(); // was ExpansionSet()
expansion = expansion.expand(tree.roots.single); // assign the result
final rows = tree.flatten(expansion: expansion);
print(rows.map((row) => row.label)); // (Repo, lib, README.md)
final diff = ListDiff.compute(rows, tree.flatten(), keyOf: (r) => r.id);
print(diff.insertedIndices); // [2]
```

## Behavior checklist

These change results without a compile error. Search first; most
projects hit a few.

```bash
grep -rnE "caseInsensitivePaths|sourceRoots|autoComputeAnchors|visibleRootId|isVirtual|virtualParent|sortChildrenByName" lib/ test/
grep -rnE "\.toggle\(|setExpanded|selectRange|selectOnly|expandedIds|selectedIds" lib/ test/
grep -rnE "filterQuery|compileFilter|ext:|hasChildren" lib/ test/
```

| Change | What to check |
|---|---|
| Paths are case SENSITIVE by default (1.x defaulted to insensitive) | Pass `TreeOptions(paths: PathPolicy.caseInsensitive)` to keep the 1.x behavior |
| Node ids are canonical paths (`/repo/lib`, lowercased when case-insensitive); 1.x ids were `node_<entry id>` and encoded folder strings | Persisted 1.x ids match nothing: map them to paths or start with an empty state |
| No synthetic `root` / `tree_root` node, no hidden levels (`autoPickVisibleRoot`) | Several top-level folders are several depth-0 rows; use `flatten(compactFolders: true)` for single-folder chains |
| No virtual entries or `virtualParent` | Give every entry a real path; mark placeholders in `data` |
| Names come from the last path segment, never from `TreeEntry.name` | Display text may change |
| Duplicate paths merge; the LATER entry wins (1.x kept the first) | Check code that relied on first-wins |
| Path parsing: whitespace is kept (1.x trimmed); a relative path escaping its root (`../x`) is skipped with `TreeIssueKind.invalidPath`; UNC paths keep `//server/share/` | Read `tree.issues`; trim input yourself if needed |
| Sibling order is natural (`file2` before `file10`) and always sorted; no input order | Update tests that asserted 1.x order |
| Colliding top-level labels read `a/src`, `b/src` (1.x `a - src`) | Update label assertions |
| Search: 1.x forced matched branches open; 2.0.0 adds the ancestors to the expansion (`expandMatches: true`), so they can be collapsed | Persist `rows.requestedExpansion`, not `rows.expansion` |
| Search syntax: `*` and `?` are globs, a term with `/` matches the path, quotes, `type:`, and `path:` have meaning; `ext:` never matches directories | Quote literal text: `"a*b"` |
| `TreeRow.hasChildren` is false when the filter hides every child | Arrow logic during search |
| `flatten` and `render` default to EVERYTHING EXPANDED (1.x required `expandedIds`) | Pass `const ExpansionState.collapsed()` for the 1.x starting view |
| State classes are immutable; methods return a new value and are `@useResult` | Assign every result; `unused_result` warnings mark dropped ones |
| Single-mode `toggle` on the selected id now clears it | Selection tests |
| Check states count leaves (files AND empty directories); an unchecked empty subfolder makes its parent `partial` | Checkbox tests |
| `ListDiff.compute` rejects a repeated key with `ArgumentError` (always in the changed middle region, elsewhere when assertions are on) and reports `changedIndices`; `isEmpty` is stricter than `isNoop` | Keys must be unique per list |
| `TreeEntry.extension` is gone; `node.path.extension` keeps case and is `''` for a name ending in `.` | Call `toLowerCase()` for the 1.x result |

## Verification

1. `dart analyze` reports no errors, no `undefined_identifier` for 1.x
   names, and no `unused_result` on `ExpansionState`, `SelectionState`, or
   `TreeRows` calls.
2. The tests pass, or every difference from the baseline is explained by
   a row of the behavior checklist.
3. For the 2.0.0 API in depth (rows, search, selection, scanner), use the
   use-directory-tree skill.

## Failure handling

- `dart fix --apply` changes nothing: the project still resolves 1.x
  (check `pubspec.lock`, re-run `dart pub get`), or the receivers are
  removed 1.x calls; do step 4 first, then run it again.
- A 1.x id string (`node_main`, `folder_...`) appears in persisted
  settings: there is no conversion function. Rebuild the state from paths
  (`tree.idOf(path)`) or drop it.
- A folder vanished after removing a file: it was inferred. Add
  `TreeEntry.directory(path)` to keep it (the 1.x `selectedDirectories`).
- Files outside the former `sourceRoots` now appear in `tree.issues` as
  `outsideRoots` (1.x dropped them silently) when using `TreeRoots.fixed`.
