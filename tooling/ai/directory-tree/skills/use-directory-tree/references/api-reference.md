# directory_tree 2.0.0 API reference

Every public type of `package:directory_tree/directory_tree.dart` and
`package:directory_tree/io.dart`, with the contracts that matter when
writing code against them. The dartdoc in the package source is the
authority; this file summarizes it.

## DirectoryTree<T>

| Member | Contract |
|---|---|
| `DirectoryTree<T>.build(entries, {options})` | Factory. Never throws on bad input; skipped input goes to `issues`. |
| `DirectoryTree.fromPaths(paths, {options})` | Static, returns `DirectoryTree<Object?>`. Trailing separator means a directory entry. |
| `DirectoryTree<T>.empty({options})` | No nodes, except `TreeRoots.fixed` roots. |
| `options` | The `TreeOptions` it was built with. |
| `nodes` | Unmodifiable pre-order `List<TreeNode<T>>`. |
| `roots`, `rootNodes` | Top-level ids and nodes, in sibling order. |
| `length`, `isEmpty`, `isNotEmpty`, `fileCount`, `directoryCount` | Counts. |
| `files`, `directories` | Lazy pre-order iterables of `FileNode<T>` / `DirectoryNode<T>`. |
| `entries` | Entries that produced nodes, first-insertion order, merged duplicates once. |
| `issues` | `List<TreeIssue<T>>`, fixed-root issues first, then input order. |
| `tree[id]`, `contains(id)` | O(1). `null` / `false` for unknown ids. |
| `idOf(path)` | The id the raw path would have; `null` only when unparseable. |
| `nodeAt(path)` | The node at a raw path, parsed with the tree's policy, or `null`. |
| `indexOf(id)`, `subtreeSizeOf(id)` | O(1); -1 and 0 for unknown ids. A file's subtree size is 1. |
| `childrenOf(id)` | Unmodifiable list in sibling order; empty for files and unknown ids. |
| `parentOf(id)` | `null` for top-level and unknown ids. |
| `rootOf(id)` | The top-level node containing `id` (itself when top level); `null` for unknown ids. |
| `ancestorsOf(id)` | Lazy, nearest first, excludes the node. |
| `descendantsOf(id)` | Lazy pre-order view, excludes the node. |
| `isAncestor(ancestor, descendant)` | Strict; false for equal or unknown ids. |
| `toBuilder()`, `rebuild(update)` | New builder / new tree seeded with `options` and `entries`; issues are not carried over. |
| `flatten(...)`, `render(...)` | See below. |
| `==` | Equal `options` and equal `nodes` in order; `issues` are not compared. |

## DirectoryTreeBuilder<T>

`DirectoryTreeBuilder<T>({options, entries})`; `options` (settable; a new
`PathPolicy` re-keys every entry), `entries` (snapshot), `length`,
`add(entry)`, `addAll(entries)`, `addFile(path, {data})`,
`addDirectory(path, {data})`, `contains(path)` (entries only, not inferred
directories), `remove(path, {recursive = true})` (returns the count;
compares by id, so a case-insensitive policy removes every spelling),
`removeWhere(test)`, `clear()`, `build()` (the builder stays usable). It
is mutable and compares by identity.

## TreeEntry<T>, TreeNode<T>, NodeId

- `const TreeEntry.file(path, {data})`, `const TreeEntry.directory(path,
  {data})`; fields `path` (raw, as given), `kind`, `data`, `isFile`,
  `isDirectory`. `==` compares path, kind, and data, not the type argument.
- `TreeNodeKind.file`, `TreeNodeKind.directory`.
- `TreeNode<T>` (sealed) = `FileNode<T>` | `DirectoryNode<T>`. `label` differs
  from `name` only for colliding top-level names (`a/src`, or the full path
  such as `C:/src` when no trailing part is unique).
- `NodeId(String value)` (const), `id.value`. Extension type: zero cost,
  compares as a string, not assignable to `String`.

## TreePath and PathPolicy

`PathPolicy.parse` rules, in order: empty input or a NUL character is a
`FormatException`; `unicodeNormalizer` runs on the raw string; separators
are `/`, plus `\` when `backslashIsSeparator`; with `backslashIsSeparator`,
a Win32 file namespace prefix is read as the path it respells
(`\\?\C:\x` is `C:/x`, `\\?\UNC\server\share\x` is `//server/share/x`),
while other `\\?\` paths (volume GUIDs) and `\\.\` device paths stay
literal UNC-like roots; `X:` followed by a separator or the end becomes
`X:/` with the letter uppercased (`C:foo` is a relative segment); exactly
two leading separators start a UNC root `//server/share/`, three or more
collapse to `/`; one leading separator is `/`; otherwise relative. Empty
and `.` segments drop; `..` removes the previous segment, stays at an
absolute root, and throws when it climbs
above a relative root. Input is not trimmed.

`TreePath` members: `TreePath.parse`, `TreePath.tryParse`, `root`,
`segments`, `isAbsolute`, `isRoot` (a path root, no segments), `name`
(`/`, `C:`, `//server/share`, `.` for roots), `extension`, `parent`
(`null` for path roots), `child(name)` (throws `ArgumentError` for `''`,
`.`, `..`, or a name with `/`, `\`, or NUL), `isWithin(ancestor)` and
`relativeTo(ancestor)` (exact, case-sensitive), `compareTo` (code units,
not natural order), `toString()` (the canonical string).

`PathPolicy` members: `caseSensitive`, `backslashIsSeparator`,
`unicodeNormalizer`, `PathPolicy.caseInsensitive`, `parse`, `tryParse`
(catches only `FormatException`), `idOf(path)`.

## TreeOptions, TreeRoots, TreeOrder

- `TreeOptions({paths, roots, order})`, `copyWith(...)`. Not generic.
- `TreeRoots.minimal()`, `.commonAncestor()`, `.fixed(paths)`,
  `.filesystem()`. A fixed root inside another collapses into the outer
  one; an unparseable fixed path is an `invalidPath` issue without entry.
- `TreeOrder.directoriesFirst`, `TreeOrder.alphabetical`,
  `TreeOrder.compareNames(a, b)`, `TreeOrder.by<T>(compare)`.
  `TreeOrder.by<T>` casts nodes to `TreeNode<T>`: using it on a tree whose
  data type is not `T` throws a `TypeError` while building.

## TreeIssue<T>

`TreeIssue({kind, path, message, entry})`; `toString()` is
`TreeIssue.<kind>(<path>): <message>`, for example
`TreeIssue.outsideRoots(/x/b.txt): The entry is outside every fixed root;
the entry was dropped.`

## TreeRows<T> and TreeRow<T>

`TreeRows`: `tree`, `expansion`, `requestedExpansion`, `filter` (`null`
when no filter or a `matchesAll` filter), `compactFolders`, `showRoots`,
`length`, `[index]`, `indexOfNode(id)`, `rowOf(id)`,
`parentIndexOf(index)`, `firstChildIndexOf(index)`, `expandNode(id)`,
`collapseNode(id)`, `toggleNode(id)`, `reveal(id)`,
`withExpansion(state, {revealMatches = false})`. Every `List` mutator
throws `UnsupportedError`.

Incremental updates equal `tree.flatten(expansion: result.expansion,
filter: filter, expandMatches: false, compactFolders: compactFolders,
showRoots: showRoots)` and never call the filter. `toggleNode` decides
from `expansion` (what is shown) and writes the same change to both
states. `reveal(id)` expands only the ancestors that decide visibility and
returns the same rows when the node is unknown, already visible, a hidden
root, or hidden by the filter with no compacted row that would show it. A
directory the filter hides but a compacted row shows (compaction follows
the tree, not the filter) is revealed through that row.

`TreeRow`: `node`, `id`, `depth`, `isExpanded` (false for files),
`hasChildren` (false for files, empty directories, and directories whose
children the filter hides), `isLast`, `guides` (`length == depth`),
`isMatch`, `chain`, `label`. Rows compare by value.

With `showRoots: false`: top-level nodes have no rows and count as
expanded; their children are depth 0; all depth-0 rows are siblings for
`isLast` and `guides`; `indexOfNode(rootId)` is -1; `parentIndexOf` of a
depth-0 row is `null`; compaction starts below the roots; a root never
produces a row even when it matches a filter.

## ExpansionState

`toJson()` gives `{'default': 'collapsed' | 'expanded', 'exceptions':
[sorted id strings]}`; `fromJson` throws `FormatException` on a missing
key or wrong type and ignores other keys. `prune(tree)` drops exceptions
that are not directories of the tree. `reveal(tree, id)` expands the
ancestors only, not the node. `toggle` always returns a new state.

## TreeQuery and TreeFilter

Further search rules beyond the SKILL.md table:

- Whitespace separates terms; a node must match all of them.
- A quote starts a phrase only at the start of a term (after an optional
  `!`) or right after a known key (`path:"my dir"`); it ends at the next
  `"` or the end of the query; no escapes.
- `!` negates only at the start of a term and only when something follows;
  a lone `!` searches for `!`.
- Keys `ext`, `type`, `path` are case-insensitive. An unknown key, empty
  value, unknown `type:` value, or `ext:` with no extension is plain text
  (`foo:bar` matches names containing `foo:bar`).
- Empty phrases (`""`) are ignored.
- A term with `/` or `\` also matches the canonical path at an occurrence
  that reaches the node's own name, so typing a compacted label
  (`lib/src/utils`) or a disambiguated top-level label (`a/src`) works.
- In a glob, `*` is any run, `?` one character, `**` is the same as `*`.
- Case-insensitive comparison uses Unicode simple case folding, the same
  table as `PathPolicy.caseInsensitive` (pinned to Unicode 18.0.0, so every
  platform agrees). It is not full case folding: `ß` does not match `ss`,
  and `İ` does not match `i`.
- Two queries are equal when `source` and `caseSensitive` are equal.

`TreeFilter` is an `abstract class` you may extend: implement
`matches(TreeNode<Object?> node)`, and override `matchesAll` only when
every node matches. `negate()` of a negation returns the original filter.

## SelectionState

`SelectionState.empty({mode = SelectionMode.single})`,
`SelectionState({mode, selected, anchor})`, `SelectionState.fromJson`.
`toJson()` gives `{'mode': 'single' | 'multiple', 'selected': [sorted
ids], 'anchor': id or null}`. `withMode(SelectionMode.single)` keeps the
anchor if it is selected, else the only selected id, else clears.
`addAll` in single mode keeps only the last id. `check` and `uncheck` keep
the anchor. `canCheck` is false for unknown ids; in single mode only a node
with at most one leaf below it can be checked.

## ListDiff and TreeDiff

`ListDiff.compute<E, K>(before, after, {required keyOf, equals})`;
`removedIndices` (descending), `insertedIndices` (ascending),
`changedIndices` (ascending, indices into `after`), `isEmpty`; all lists
unmodifiable. `TreeDiff.compute(before, after)`; `added` and `changed` in
the new tree's pre-order, `removed` in the old tree's; `isEmpty`.

## TreeStyle

`TreeStyle({branch, lastBranch, pipe, gap})`, presets `unicode`, `ascii`,
`indent`. Use equal widths so columns line up.

## DirectoryScanner (package:directory_tree/io.dart)

- Entries are sorted by `String.compareTo` on the path, so a scan of an
  unchanged directory is identical every run.
- Paths are exactly what `dart:io` reports: the scan path as given plus
  the platform separator and names. `scanTree` makes a relative path that
  climbs above its start (`..`, `../project`) absolute first, and on Linux
  and macOS scans `//x` as `/x` and a relative `C:` as `./C:`; `scan` and
  `scanSync` never rewrite paths.
- With `followLinks: true`, links to directories are entered and reported
  as directories, links to files as files; broken links and links that
  would close a cycle stay `Link` file entries.
- On Windows, the scan root, directories, and followed links past
  `MAX_PATH` are retried through the `\\?\` extended-length form; only a
  failed retry reaches `onError` (or, for the root, throws).
- `skip` and `onError` run synchronously inside the walk; an exception
  they throw aborts the scan.
