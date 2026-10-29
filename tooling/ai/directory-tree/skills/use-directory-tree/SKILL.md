---
name: use-directory-tree
description: Use when writing or reviewing Dart/Flutter code in a project that depends on directory_tree 2.x - building a DirectoryTree from paths or TreeEntry values, DirectoryTreeBuilder and rebuild, TreePath and PathPolicy (case sensitivity, Windows and UNC paths), TreeRoots and TreeOrder, TreeIssue, NodeId lookups, flatten to TreeRows and TreeRow for a tree view, ExpansionState with expandNode/collapseNode/toggleNode/reveal and persisting requestedExpansion, TreeQuery search syntax and matchRanges highlighting, TreeFilter, SelectionState with range selection and tri-state checkboxes, ListDiff for AnimatedList, TreeDiff after a rescan, render with TreeStyle, or DirectoryScanner from package directory_tree/io.dart.
---

# Use directory_tree 2.x correctly

directory_tree 2.0.0 is a rewrite. No 1.x name survives with its old shape,
and agents trained on 1.x guess wrong names (`TreeBuilder`, `TreeData`,
`FlattenStrategy`, `ExpansionSet`, `SelectionSet`, `VisibleNode`). Use the
names below.

## Step 0: inspect the project

1. Resolved version: `dart pub deps --style=compact | grep '^- directory_tree '`
   (`flutter pub deps` in a Flutter app). This skill documents 2.x. For a
   1.x project, use the migrate-directory-tree-v1-to-v2 skill first.
2. Imports:
   - `import 'package:directory_tree/directory_tree.dart';` is the whole
     core API. It is pure Dart and runs on the VM, Flutter, JavaScript,
     and WebAssembly.
   - `import 'package:directory_tree/io.dart';` adds only
     `DirectoryScanner`. It needs `dart:io` (not on the web) and does NOT
     re-export the core, so import both.

## Exact names (verified against source)

| Task | WRONG guesses | 2.0.0 API |
|---|---|---|
| Tree from path strings | `TreeBuilder().build(...)` | `DirectoryTree.fromPaths(paths, options: ...)`, a static method returning `DirectoryTree<Object?>` |
| Tree with typed data | `TreeEntry(id:, name:, fullPath:)` | `DirectoryTree<T>.build([TreeEntry.file(path, data: x), TreeEntry.directory(path)])` |
| Incremental building | mutate nodes | `DirectoryTreeBuilder<T>()..addFile(p)..addDirectory(p)..remove(p)`, then `build()`; or `tree.rebuild((b) => b..addFile(p))` |
| Node by path | scan `nodes` | `tree.nodeAt('/repo/lib')`, `tree.idOf('/repo/lib')` |
| Node by id | `tree.nodes[id]` | `tree[id]` (`nodes` is a pre-order `List`) |
| Visible rows | `FlattenStrategy`, `VisibleNode` | `tree.flatten(...)` returns `TreeRows<T>`, a `List<TreeRow<T>>` |
| Expand a row | `rows.expand(id)` | `rows.expandNode(id)`, `collapseNode`, `toggleNode`, `reveal` |
| Expansion state | `ExpansionSet` | `ExpansionState` (immutable) |
| Selection state | `SelectionSet`, `SelectionMode.multi` | `SelectionState`, `SelectionMode.multiple` |
| Folder checkbox | `folderSelection(...)`, `FolderSelection` | `selection.checkStateOf(tree, id)`, `CheckState.unchecked/partial/checked` |
| Search filter | `compileFilter(q)` | `TreeQuery.parse(q)` |
| Row diff | `diffVisibleNodes`, `removeIndicesDesc` | `ListDiff.compute(before, after, keyOf: (row) => row.id)`, `removedIndices`, `insertedIndices`, `changedIndices` |
| Entry path | `entry.fullPath` | `entry.path` |
| Node kind | `node.type`, `NodeType.folder` | `node.kind`, `TreeNodeKind.directory`, `node.isFile`, `node.isDirectory` |
| Ancestors | `ancestorChain` | `tree.ancestorsOf(id)` (nearest first, excludes the node) |

`rows.expand(...)` compiles, because `TreeRows` is a `List` and
`Iterable.expand` exists, but it does not expand a folder. Always use
`expandNode`.

## Building

```dart
final tree = DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/main.dart',
  '/repo/assets/', // trailing separator: a directory entry
  '/repo/README.md',
]);
print(tree.rootNodes.single.name); // repo
print(tree.fileCount); // 3
print(tree.nodeAt('/repo/assets')!.isExplicit); // true
print(tree.nodeAt('/repo/lib')!.isExplicit); // false
```

- `fromPaths` makes a file entry per path, and a directory entry for a path
  ending in `/` (or `\` when `backslashIsSeparator`). It returns
  `DirectoryTree<Object?>`; `DirectoryTree<int>.fromPaths` does not compile.
  For typed data use `DirectoryTree<T>.build` with `TreeEntry<T>` values.
- Directories that only contain entries are inferred: `entry == null`,
  `isExplicit == false`. An inferred directory disappears with its last
  file; add `TreeEntry.directory(path)` (or `builder.addDirectory`) to keep
  it, or to attach data to a directory.
- Entries whose paths map to the same `NodeId` merge: the later entry wins
  and keeps the first one's position.
- Building never throws on bad input; see Issues.
- Trees are immutable. `rebuild(update)` and `toBuilder()` derive a new
  tree; unchanged paths keep their ids. `DirectoryTreeBuilder.remove(path)`
  is recursive by default (`recursive: false` removes only that entry) and
  returns the number of entries removed. `DirectoryTree.empty()` has no
  nodes, except the roots of `TreeRoots.fixed`.
- Data takes part in `==` of entries, nodes, and trees; give it value
  equality if trees are compared.

## Nodes, ids, and lookups

- `TreeNode<T>` is sealed: `FileNode<T>` or `DirectoryNode<T>`, so a
  `switch` is exhaustive. Fields: `id`, `path` (`TreePath`), `name` (last
  segment), `label` (display text), `parent` (`NodeId?`, `null` at top
  level), `depth` (0 at top level), `entry`, `data`, `isExplicit`, `kind`,
  `isFile`, `isDirectory`, `isRoot` (top level in this tree, not
  `TreePath.isRoot`). `DirectoryNode.children` is a `List<NodeId>`; use
  `tree.childrenOf(id)` for nodes.
- `NodeId` is an extension type over the canonical path string: `id.value`
  to persist, `NodeId(saved)` to restore. It is not a `String`. Derive ids
  with `tree.idOf(path)` or `policy.idOf(treePath)`, never by formatting
  strings: under a case-insensitive policy ids are case-folded
  (Unicode simple case folding, so `README.md` gives `readme.md`).
- `tree.idOf(path)` returns the id whether or not the tree has that node,
  and `null` only for an unparseable path. `nodeAt(path)` returns the node
  or `null`.
- Tree members: `nodes` (pre-order, unmodifiable), `length`, `isEmpty`,
  `fileCount`, `directoryCount`, `files`, `directories`, `entries`,
  `issues`, `roots` (`List<NodeId>`), `rootNodes`, `tree[id]`,
  `contains(id)`, `indexOf(id)`, `subtreeSizeOf(id)`, `childrenOf(id)`,
  `parentOf(id)`, `rootOf(id)`, `ancestorsOf(id)`, `descendantsOf(id)`,
  `isAncestor(a, b)` (strict). A subtree is `nodes` from `indexOf(id)` for
  `subtreeSizeOf(id)` nodes.
- Unknown ids never throw: lookups return `null`, -1, 0, `false`, or an
  empty result; row updates and tree-aware state operations return the
  same object.

## Paths and PathPolicy

- `TreePath.parse(raw)` / `TreePath.tryParse(raw)` use the default policy.
  Parsing is pure string work, the same on every host: separators become
  `/`, empty and `.` segments drop, `..` resolves, drive letters uppercase.
  `TreePath.parse(r'C:\work\..\repo\')` is `C:/repo`. A relative path that
  climbs above its start (`../x`), an empty path, or a NUL character throws
  `FormatException` from `parse` (`tryParse` returns `null`).
- Roots: `''` (relative, named `.`), `/`, `C:/` (named `C:`),
  `//server/share/` (UNC).
- `TreePath`: `root`, `segments`, `name`, `extension`, `parent`,
  `child(name)`, `isWithin(ancestor)`, `relativeTo(ancestor)`,
  `isAbsolute`, `isRoot`. `extension` is only the last one and keeps case:
  `archive.tar.gz` gives `.gz`, `.env` gives `''`.
- `PathPolicy({caseSensitive = true, backslashIsSeparator = true,
  unicodeNormalizer})`, `PathPolicy.caseInsensitive`. Pass it as
  `TreeOptions(paths: ...)`. Case-insensitive trees merge `README.md` and
  `readme.md` into one node, keep a display spelling, and case-fold ids.
  `unicodeNormalizer` (for example NFC) must be pure, idempotent, and
  normalize each segment on its own (the Unicode normal forms do; `trim`
  does not); pass the same function object or options compare unequal.

## Options: roots and order

`TreeOptions({paths, roots, order})` has defaults for everything:
case-sensitive, `TreeRoots.minimal()`, `TreeOrder.directoriesFirst`.

- `TreeRoots.minimal()` (default): the outermost directories that hold
  entries. `/ws/a/src/x.dart` and `/ws/b/src/y.dart` give two
  roots labelled `a/src` and `b/src`; colliding top-level names get the
  shortest unique trailing path as `label`, `name` stays `src`.
  Minimal roots MOVE when entries change: removing `/repo/README.md` from
  a tree whose other files are under `/repo/lib` makes `lib` the root, and
  the `/repo` node and its id disappear. For a stable root, add
  `TreeEntry.directory('/repo')` or use `TreeRoots.fixed(['/repo'])`.
- `TreeRoots.commonAncestor()`: one root per path root, at the deepest
  directory containing everything.
- `TreeRoots.fixed([...])`: exactly these directories, present even when
  empty. Entries outside them become `outsideRoots` issues; a file entry
  equal to a root is a `conflict`.
- `TreeRoots.filesystem()`: the path roots themselves (`/`, `C:`).
- Order is a `NodeComparator` (`int Function(TreeNode<Object?>,
  TreeNode<Object?>)`): `TreeOrder.directoriesFirst`,
  `TreeOrder.alphabetical`, or `TreeOrder.by<T>((a, b) => ...)` for typed
  data. `TreeOrder.compareNames` is natural (`file2` before `file10`) and
  case-insensitive, then exact code units. Ties break by id. There is no
  input-order mode.
- Options compare comparators by identity, and every `TreeOrder.by` call
  returns a new function. Store it once (a `final` field or top-level
  variable) when trees built with it must compare equal.

## Issues

`tree.issues` lists every skipped input in input order (fixed-root issues
first). `TreeIssue` has `kind`, `path` (raw), `entry` (`null` for a bad
fixed root), and a stable `message`. Kinds: `TreeIssueKind.invalidPath`
(empty, NUL, escaping `..`, or a file entry at a path root),
`TreeIssueKind.conflict` (a file entry where a directory must be),
`TreeIssueKind.outsideRoots`. Show them; do not wrap `build` in try/catch.

## Rows and expansion

```dart
final tree = DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/main.dart',
  '/repo/README.md',
]);
var rows = tree.flatten(expansion: const ExpansionState.collapsed());
print(rows.map((row) => row.label)); // (repo)
rows = rows.toggleNode(rows.first.id); // the user clicked "repo"
print(rows.map((row) => row.label)); // (repo, lib, README.md)
final lib = tree.idOf('/repo/lib')!;
final opened = rows.expandNode(lib);
print(opened.length); // 5
print(identical(opened.last, rows.last)); // true
final saved = rows.requestedExpansion.toJson(); // persist this
print(saved); // {default: collapsed, exceptions: [/repo]}
```

- `flatten({expansion = const ExpansionState.expanded(), filter,
  expandMatches = true, compactFolders = false, showRoots = true})`. The
  default shows EVERY directory expanded; pass
  `const ExpansionState.collapsed()` for a view that starts closed.
- `TreeRows` is an unmodifiable `List` (`add`, `removeAt`, `sort` throw
  `UnsupportedError`); use it as `itemCount: rows.length` with `row.id` as
  the key. `TreeRow`: `id`, `node`, `depth`, `label`, `isExpanded`,
  `hasChildren`, `isLast`, `guides` (connector columns), `isMatch`,
  `chain` (compacted directories).
- `expandNode`, `collapseNode`, `toggleNode`, `reveal` return NEW rows and
  reuse every unchanged `TreeRow` object (`identical`). Assign the result.
  Unknown ids and files return the same rows. Collapsing keeps the state of
  folders below, so expanding again restores them.
- Keyboard: `indexOfNode(id)` (-1 when hidden), `rowOf(id)`,
  `parentIndexOf(index)` (left arrow), `firstChildIndexOf(index)` (right
  arrow); up and down are `index - 1` and `index + 1`.
- `rows.withExpansion(state, {revealMatches = false})` applies a state
  built elsewhere without calling the filter again.
- `rows.expansion` is what the rows show, including folders a search
  opened. `rows.requestedExpansion` excludes those. PERSIST
  `requestedExpansion` (`toJson()`, a map ready for `jsonEncode`), restore
  with `ExpansionState.fromJson(map)`, then `prune(tree)` after a rebuild.
- `ExpansionState` is immutable; every method returns a new value (or the
  same one when nothing changes) and is `@useResult`:
  `ExpansionState.collapsed()`, `.expanded()`, `.withExpanded(ids)`,
  `.withCollapsed(ids)`, `.fromJson(map)`; `isExpanded(id)`, `expand`,
  `collapse`, `toggle`, `setExpanded(id, expanded: b)`, `expandAll(ids)`,
  `collapseAll(ids)` (only those ids; for "collapse everything" use
  `const ExpansionState.collapsed()`), `reveal(tree, id)` (expands the
  ancestors), `expandSubtree(tree, id)`, `collapseSubtree(tree, id)`,
  `prune(tree)`, `toJson()`, `expandsByDefault`, `exceptions`.
- `compactFolders: true` shows single-child directory chains on one row
  (`app/lib/src`); the row expands as its deepest directory (`row.node`).
- `showRoots: false` drops the top-level rows: their children become depth
  0, top-level ids have no row, and `expandNode`/`collapseNode`/
  `toggleNode` ignore them. Combine with `TreeRoots.fixed([workspace])` to
  hide a workspace root.

## Search and filters

```dart
final project = DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/src/tree.g.dart',
  '/repo/test/tree_test.dart',
  '/repo/README.md',
]);
List<String> find(String text) => project.nodes
    .where(TreeQuery.parse(text).matches)
    .map((node) => node.name)
    .toList();
print(find('tree !*.g.dart')); // [tree.dart, tree_test.dart]
print(find('ext:md')); // [README.md]
print(find('type:dir path:lib')); // [lib, src]
print(find('src/')); // [tree.dart, tree.g.dart]
final ranges = TreeQuery.parse('TREE').matchRanges('tree_test.dart');
print(ranges); // [(end: 4, start: 0)]
```

`TreeQuery.parse(text, {caseSensitive = false})` never throws; unknown
syntax is searched literally. A node matches when it matches EVERY term.

| Term | Matches |
|---|---|
| `main` | names containing `main` |
| `"my notes"` | names containing the phrase; quoted text is literal (`"a*b"`) |
| `!term` | nodes not matching `term` (any term kind) |
| `*.dart`, `test_?.md` | WHOLE names matching the glob |
| `ext:dart`, `ext:dart,md`, `ext:tar.gz` | FILES whose name ends with `.dart` (suffix test); directories never match |
| `type:file`, `type:dir` (`f`, `d`, `directory`) | files or directories |
| `path:lib/src` | canonical path contains `lib/src` |
| `lib/src` | the node `src` under a path containing `lib/src` |
| `lib/` | direct children of a folder whose path ends with `lib` |
| `src/*.dart` | nodes whose last path components match the glob |

- `ext:` and `type:` always ignore case; other terms follow
  `caseSensitive`. Plain terms and globs look at the name only.
- An empty or whitespace query reports `matchesAll`, and `flatten` then
  skips filtering (`rows.filter` is `null`). `*` does not report
  `matchesAll`.
- `matchRanges(text)` returns sorted, merged `({int start, int end})`
  records for positive plain terms only (no globs, keys, or negations).
  Pass the displayed text, such as `row.label`.
- `TreeFilter.where<Object?>((node) => ...)`, `TreeFilter.all`, and the
  combinators `and`, `or`, `negate`. A `TreeFilter.where<int>` only matches
  `TreeNode<int>`, so on a `fromPaths` tree (`Object?` data) it matches
  nothing; use `<Object?>` unless the tree is typed.
- A filtered view keeps matches plus their ancestors; `row.isMatch`
  separates them (true for every row without a filter). `expandMatches:
  true` opens every ancestor of a match; `false` keeps matches inside
  collapsed folders hidden. `flatten` calls the filter once per node and
  updates never call it again, so a filter must be pure. A filter that
  matches nothing gives empty rows.

## Selection and checkboxes

```dart
final tree = DirectoryTree.fromPaths([
  '/repo/lib/main.dart',
  '/repo/lib/util.dart',
  '/repo/README.md',
]);
final lib = tree.idOf('/repo/lib')!;
var checks = const SelectionState.empty(mode: SelectionMode.multiple);
checks = checks.check(tree, lib);
print(checks.checkStateOf(tree, lib)); // CheckState.checked
final repo = tree.roots.single;
print(checks.checkStateOf(tree, repo)); // CheckState.partial
print(checks.isSelected(lib)); // false
print(const SelectionState.empty().canCheck(tree, lib)); // false
```

- `SelectionState.empty()` defaults to `SelectionMode.single`. Pass
  `mode: SelectionMode.multiple` for multi-select and checkbox trees.
- Clicks: `select(id)` (plain click, sets the anchor), `toggle(id)`
  (ctrl-click; in single mode toggling the selected id clears it),
  `extendTo(id, rows.map((row) => row.id))` (shift-click; keeps the
  anchor, selects in display order), `addAll`, `removeAll`, `clear`,
  `withAnchor`, `withMode`, `prune(tree)`. Read with `selected`,
  `isSelected`, `anchor`, `length`, `isEmpty`.
- Checkboxes are defined over leaves (files and empty directories):
  `check(tree, id)` selects the leaves below `id`, NOT the directory id;
  `uncheck(tree, id)` deselects them. The checkbox click handler is
  `selection = selection.toggleCheck(tree, id)`: it unchecks a checked
  node and checks an unchecked or partial one. Draw with
  `checkStateOf(tree, id)` or `checkStates(tree)` (every node in one
  pass). In single mode, `check` and `toggleCheck` on a directory with
  more than one leaf throw `StateError`; ask `canCheck(tree, id)` first.
- `SelectionState(mode: SelectionMode.single, selected: [a, b])` throws
  `ArgumentError`. Persist with `toJson()` / `SelectionState.fromJson`.
- Every method is immutable and `@useResult`; a no-op returns the same
  object, so `identical(next, state)` means nothing changed.

## Diffs

```dart
final tree = DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/main.dart',
  '/repo/README.md',
]);
final before = tree.flatten();
final after = before.collapseNode(tree.idOf('/repo/lib')!);
final diff = ListDiff.compute(before, after, keyOf: (row) => row.id);
print(diff.removedIndices); // [4, 3, 2]
print(diff.insertedIndices); // []
print(diff.changedIndices); // [1]
```

- `ListDiff.compute(before, after, keyOf: ..., equals: ...)`: apply
  `removedIndices` first (descending, as given), then `insertedIndices`
  (ascending, as given). That is Flutter's `AnimatedList` protocol:
  `removeItem` per removed index, then `insertItem` per inserted index.
  `changedIndices` kept their place but differ by `equals` (default `==`);
  rebuild them without animation. `isEmpty` requires all three empty. A
  move is one removal plus one insertion.
- Keys must be unique within each list. A duplicate in the changed middle
  region throws `ArgumentError`; one in the common prefix or suffix is
  only caught when assertions are enabled.
- `TreeDiff.compute(before, after)` matches nodes by id and reports
  `added`, `removed`, `changed` (kind, path spelling, label, entry, or
  parent differs). It ignores sibling order and depth changes on their
  own. Both trees need the same `PathPolicy`. Use it after a rescan to
  drop cached state; use `ListDiff` for row order.

## Rendering text

`tree.render({style = TreeStyle.unicode, expansion, filter,
compactFolders, showRoots, maxDepth, label})` returns the visible rows as
lines joined by `\n`, with no trailing newline (empty tree: `''`).
Directories get a trailing `/` unless `label` is given, which replaces the
default text. `maxDepth: 0` prints only depth-0 rows; a negative
`maxDepth` prints nothing. Styles: `TreeStyle.unicode` (`├── `),
`TreeStyle.ascii` (`|-- `), `TreeStyle.indent`, or
`TreeStyle(branch:, lastBranch:, pipe:, gap:)`. A filter always reveals
its matches here.

## Scanning the file system

```dart
// import 'dart:io' and 'package:directory_tree/io.dart' as well
final scanner = DirectoryScanner(
  maxDepth: 2,
  skip: (entity) =>
      entity.path.endsWith('${Platform.pathSeparator}build'),
  onError: (error) => print('skipped ${error.path}'),
);
final scanned = await scanner.scanTree(projectPath);
print(scanned.rootNodes.length); // 1
```

- `DirectoryScanner({includeHidden = false, followLinks = false,
  maxDepth, skip, onError})`. `scan(path)` returns
  `Future<List<TreeEntry<FileSystemEntity>>>`, `scanSync(path)` the same
  list synchronously, `scanTree(path, {options})` a
  `Future<DirectoryTree<FileSystemEntity>>`.
- The scanned directory is included as a directory entry, so `scanTree`
  has that directory as its single root. Node `data` is the `File`,
  `Directory`, or `Link`.
- `maxDepth` counts levels below the scanned directory: 0 returns only the
  root, 1 adds its children; directories at the limit are reported but not
  listed. Negative throws `ArgumentError` when the scan starts.
- Names starting with `.` are skipped unless `includeHidden`. `skip`
  returning true prunes the entity and its subtree without listing it.
  Links are reported as files with `Link` data unless `followLinks`.
- An unreadable directory goes to `onError` (a `FileSystemException`) and
  the walk continues. A missing scan path throws `PathNotFoundException`;
  a file path throws `FileSystemException`.

## Verification

After edits: `dart analyze` the touched paths and run the project's tests.
`@useResult` warnings (`unused_result`) on `ExpansionState`,
`SelectionState`, or `TreeRows` calls mean a dropped result: assign it.

## Failure handling

- `Undefined name 'TreeBuilder'` / `'ExpansionSet'` / `'FlattenStrategy'`:
  1.x code; use the migrate-directory-tree-v1-to-v2 skill.
- `The getter 'fullPath' isn't defined` or `removeIndicesDesc`: run
  `dart fix --apply` (the package ships these renames).
- A typed variable rejects `DirectoryTree.fromPaths`: it is
  `DirectoryTree<Object?>`; build with `DirectoryTree<T>.build`.
- A node lookup returns `null` for a path that exists: the tree is
  case-insensitive and the id was built by hand, or the path is relative
  versus absolute. Use `tree.idOf(path)` / `tree.nodeAt(path)`.
- A view does not change after a click: the result of `toggleNode` or of
  an `ExpansionState` method was not assigned.
- A search opened folders that stay open after clearing it: the code
  persisted `rows.expansion`; persist `rows.requestedExpansion`.
- `TreeDiff.compute` is empty after a sort change: expected, it ignores
  order; diff the rows with `ListDiff`.

For per-type member lists and the full search rules, read
[references/api-reference.md](references/api-reference.md).
