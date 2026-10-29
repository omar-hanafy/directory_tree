# directory_tree

Turn a list of file paths into an immutable, indexed directory tree, then
show it: flattened rows for a virtualized list, search with highlighting,
selection with tri-state checkboxes, diffs for animated lists, and text
output like the `tree` command.

The package is pure Dart. It never touches the file system unless you import
the optional scanner, so it runs the same on the VM, in Flutter apps, and on
the web (JavaScript and WebAssembly). Use it for file explorers, IDE-style
side panels, file pickers, repository viewers, and CLI tree printers.

The same paths in any order give an equal tree with the same node order and
the same node ids, so ids can key widget state, expansion, and selection
across rebuilds.

Coding agents can learn the 2.0.0 API and the upgrade from 1.x from the
[plugin for AI coding assistants](#ai-coding-assistant-support) (Claude
Code, Codex, and Antigravity).

## Install

```sh
dart pub add directory_tree
```

In a Flutter project, `flutter pub add directory_tree` does the same.

```dart
import 'package:directory_tree/directory_tree.dart';
```

## Quick start

Build a tree from paths and print it:

```dart
final tree = DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/main.dart',
  '/repo/test/tree_test.dart',
  '/repo/README.md',
]);
print(tree.render());
```

```text
repo/
├── lib/
│   ├── src/
│   │   └── tree.dart
│   └── main.dart
├── test/
│   └── tree_test.dart
└── README.md
```

Directories come before files, and names sort naturally without regard to
case. `lib` and `src` were never listed: a directory that contains an entry
is created for you.

A UI shows the tree as rows. `flatten` returns the visible rows for an
expansion state, and `toggleNode` updates them when the user clicks an
arrow:

```dart
var rows = tree.flatten(expansion: const ExpansionState.collapsed());
rows = rows.toggleNode(rows.first.id); // the user opened "repo"

for (final row in rows) {
  final arrow = row.hasChildren ? (row.isExpanded ? 'v ' : '> ') : '  ';
  print('${'  ' * row.depth}$arrow${row.label}');
}
```

```text
v repo
  > lib
  > test
    README.md
```

`TreeRows` is an unmodifiable `List<TreeRow>`, so in Flutter it plugs into
`ListView.builder(itemCount: rows.length, ...)`, with `row.id` as the key.
The examples below keep using this `tree`.

## Core concepts

### Paths and `PathPolicy`

Each raw path is parsed into a canonical `TreePath`. Parsing is pure string
work and does not depend on the host, so POSIX paths, Windows drive paths,
and UNC paths parse the same on Linux, macOS, Windows, and the web:

```dart
print(TreePath.parse(r'C:\work\..\repo\')); // C:/repo
print(TreePath.parse(r'\\server\share\a.txt').root); // //server/share/
print(TreePath.parse('a//./b/')); // a/b
print(TreePath.tryParse('../outside')); // null
```

Separators become `/`, empty and `.` segments are dropped, `..` is resolved,
and drive letters are uppercased. A relative path that climbs above its
start is invalid. The full rules are on `PathPolicy.parse`.

A `PathPolicy` decides three things for a whole tree, through
`TreeOptions.paths`:

- `caseSensitive` (default `true`): whether `README.md` and `readme.md` are
  different nodes. Use `PathPolicy.caseInsensitive` for trees that mirror
  Windows or default macOS volumes.
- `backslashIsSeparator` (default `true`): set it to `false` only when your
  POSIX file names contain literal backslashes.
- `unicodeNormalizer` (default none): a function applied to every raw path,
  typically NFC normalization, so names created on macOS (often NFD) match
  names from other sources.

```dart
const paths = ['/Repo/README.md', '/repo/readme.md'];
print(DirectoryTree.fromPaths(paths).fileCount); // 2

final folded = DirectoryTree.fromPaths(
  paths,
  options: const TreeOptions(paths: PathPolicy.caseInsensitive),
);
print(folded.fileCount); // 1
print(folded.files.single.path); // /repo/readme.md
```

A case-insensitive tree keeps a display spelling for each node; only
identity ignores case.

### Entries with typed data

`DirectoryTree.fromPaths` is the quick way in. To attach data to nodes, build
from `TreeEntry` values with a type argument:

```dart
final sized = DirectoryTree<int>.build([
  TreeEntry.file('/repo/lib/main.dart', data: 1024),
  TreeEntry.file('/repo/README.md', data: 300),
  TreeEntry.directory('/repo/assets'),
]);
print(sized.nodeAt('/repo/lib/main.dart')!.data); // 1024
print(sized.nodeAt('/repo/assets')!.isExplicit); // true
print(sized.nodeAt('/repo/lib')!.isExplicit); // false
```

A directory entry keeps an empty directory in the tree and can carry data.
Directories created because entries lie inside them are inferred: they have
no entry and `isExplicit` is false. Two entries whose paths map to the same
node merge, and the later one wins.

Nodes are `FileNode` or `DirectoryNode` (a sealed pair, so a `switch` over a
node is exhaustive). Data takes part in `==`, so give it value equality if
you compare trees.

### Ids and lookups

Every node has a `NodeId`: the policy key of its canonical path. Ids are
stable across rebuilds, so they are the keys to store. Persist one with
`id.value` and restore it with `NodeId(saved)`.

```dart
final lib = tree.idOf('/repo/lib')!;
print(lib.value); // /repo/lib
print(tree.childrenOf(lib).map((node) => node.name)); // (src, main.dart)

final file = tree.nodeAt('/repo/lib/src/tree.dart')!;
print(tree.parentOf(file.id)!.name); // src
print(tree.ancestorsOf(file.id).map((n) => n.name)); // (src, lib, repo)
print(tree.isAncestor(lib, file.id)); // true
```

`tree.nodes` holds every node in pre-order, and a node's subtree is the
slice that starts at `indexOf(id)` and is `subtreeSizeOf(id)` long. Lookup
by id, `parentOf`, `isAncestor`, and the subtree range are O(1);
`descendantsOf` is a view of that slice.

### Roots

`TreeOptions.roots` picks the top-level nodes:

```dart
const sources = ['/home/me/a/src/x.dart', '/home/me/b/src/y.dart'];
for (final roots in const [
  TreeRoots.minimal(),
  TreeRoots.commonAncestor(),
  TreeRoots.fixed(['/home/me']),
  TreeRoots.filesystem(),
]) {
  final rooted = DirectoryTree.fromPaths(
    sources,
    options: TreeOptions(roots: roots),
  );
  final labels = rooted.rootNodes.map((node) => node.label).join(', ');
  print('$roots: $labels');
}
```

```text
TreeRoots.minimal(): a/src, b/src
TreeRoots.commonAncestor(): me
TreeRoots.fixed(/home/me): me
TreeRoots.filesystem(): /
```

- `minimal` (the default) starts at the outermost directories that hold
  entries, without empty chains of single directories above them.
- `commonAncestor` gives one root per path root (`/`, each drive, each UNC
  share), at the deepest directory that contains everything.
- `fixed` uses exactly the directories you list. They exist even when empty,
  and entries outside them are reported as issues.
- `filesystem` starts at the path roots themselves, like a file manager.

When top-level names collide, their labels grow to the shortest unique
trailing path (`a/src`, `b/src`). `node.name` stays `src`.

### Ordering

`TreeOptions.order` sorts siblings. The default, `TreeOrder.directoriesFirst`,
puts directories first; `TreeOrder.alphabetical` interleaves them. Both
compare names with `TreeOrder.compareNames`: natural order (`file2` before
`file10`) without regard to case.

```dart
final names = DirectoryTree.fromPaths([
  '/d/file10.txt',
  '/d/file2.txt',
  '/d/Beta/',
  '/d/alpha.txt',
]);
print(names.render());
```

```text
d/
├── Beta/
├── alpha.txt
├── file2.txt
└── file10.txt
```

A path that ends with a separator, like `/d/Beta/`, becomes a directory
entry in `fromPaths`.

To order by your data, wrap a typed comparator with `TreeOrder.by`. Ties are
broken by node id, so the order is always total and deterministic:

```dart
final bySizeDescending = TreeOrder.by<int>(
  (a, b) => (b.data ?? 0).compareTo(a.data ?? 0),
);
const files = [
  TreeEntry.file('/repo/small.txt', data: 10),
  TreeEntry.file('/repo/big.bin', data: 4096),
  TreeEntry.file('/repo/mid.md', data: 300),
];
final bySize = DirectoryTree<int>.build(
  files,
  options: TreeOptions(order: bySizeDescending),
);
print(bySize.files.map((n) => n.name)); // (big.bin, mid.md, small.txt)
```

Trees compare their options, and options compare comparators by identity,
so store a `TreeOrder.by` result once when trees built with it must compare
equal.

### Issues instead of exceptions

Bad input never throws while building. The tree skips it and lists a
`TreeIssue` for each skipped input, in input order:

```dart
final checked = DirectoryTree.fromPaths([
  '',
  '../up.txt',
  '/r/a.txt',
  '/r/a.txt/b.txt',
]);
for (final issue in checked.issues) {
  print(issue);
}
```

```text
TreeIssue.invalidPath(): Path is empty; the entry was skipped.
TreeIssue.invalidPath(../up.txt): Relative path escapes its root; the entry was skipped.
TreeIssue.conflict(/r/a.txt): The file entry is an ancestor of another entry, so the path is a directory; the file entry was dropped.
```

The kinds are `invalidPath`, `conflict` (a file where a directory must be),
and `outsideRoots` (an entry outside every `TreeRoots.fixed` root). Each
issue has the raw `path`, the skipped `entry`, and a stable `message` you
can show next to a file picker.

### Updating a tree

Trees are immutable. Derive a changed tree with `rebuild`, or keep a
`DirectoryTreeBuilder` and call `build` whenever you need a snapshot:

```dart
final next = tree.rebuild(
  (builder) => builder
    ..addFile('/repo/lib/src/rows.dart')
    ..remove('/repo/test'),
);
print(next.render());
```

```text
repo/
├── lib/
│   ├── src/
│   │   ├── rows.dart
│   │   └── tree.dart
│   └── main.dart
└── README.md
```

`remove` takes a subtree with it unless you pass `recursive: false`.
Unchanged paths keep their ids, so expansion and selection state carries
over. The top level can still move: with the default
`TreeRoots.minimal()`, removing `/repo/README.md` from a tree whose other
files are all under `/repo/lib` makes `lib` the top-level node and removes
`/repo`. Pin the top level with `TreeRoots.fixed` or a directory entry when
that matters. `rebuild` runs a full build; see the performance numbers
below.

## Views

### Rows and expansion

`flatten` turns a tree into `TreeRows`, the rows a tree view shows. Each
`TreeRow` has what a row widget needs: `id`, `node`, `depth`, `label`,
`isExpanded`, `hasChildren`, `isLast` and `guides` (for connector lines),
and `isMatch` (for search). By default every directory is expanded.

An `ExpansionState` is a default (all expanded or all collapsed) plus the
ids that differ from it, so it stays small for any tree size. It is an
immutable value keyed by `NodeId`, so it survives rebuilds; `prune(tree)`
drops ids the tree no longer has.

### Incremental updates

`expandNode`, `collapseNode`, `toggleNode`, and `reveal` return new rows
without flattening again. They build only the rows that change and reuse
every other `TreeRow` object, so a list view can compare rows with
`identical` to decide what to rebuild:

```dart
final expanded = tree.flatten();
final collapsed = expanded.collapseNode(tree.idOf('/repo/lib')!);
print(expanded.length); // 8
print(collapsed.length); // 5
print(identical(collapsed.last, expanded.last)); // true
```

The `lib` row itself is a new object, since its `isExpanded` changed; the
rows before it and after its removed descendants are the same objects.
Collapsing keeps the state of the folders below, so expanding again
restores them. Unknown ids and files return the same rows object.

### Compact folders and hidden roots

`compactFolders: true` shows a chain of single-child directories on one
row, as VS Code does. `showRoots: false` drops the top-level rows, which
suits an explorer of one folder whose name is a title. Combine it with
`TreeRoots.fixed` to hide a workspace root:

```dart
const workspacePaths = ['/work/app/lib/src/main.dart', '/work/README.md'];
final workspace = DirectoryTree.fromPaths(
  workspacePaths,
  options: const TreeOptions(roots: TreeRoots.fixed(['/work'])),
);
print(workspace.render(compactFolders: true, showRoots: false));
```

```text
app/lib/src/
└── main.dart
README.md
```

A compacted row's `chain` lists its directories, and it expands and
collapses as its deepest directory (`row.node`).

### Keyboard navigation

```dart
final rows = tree.flatten();
final src = rows.indexOfNode(tree.idOf('/repo/lib/src')!);
print(rows[src].label); // src
print(rows[rows.parentIndexOf(src)!].label); // lib
print(rows[rows.firstChildIndexOf(src)!].label); // tree.dart
print(rows.firstChildIndexOf(rows.length - 1)); // null
```

`parentIndexOf` is the left arrow, `firstChildIndexOf` the right arrow, and
up and down are `index - 1` and `index + 1`. `indexOfNode` returns -1 for a
node that is not visible, and also finds a directory inside a compacted
row.

### Revealing a node

`reveal` expands the collapsed ancestors of a node, so a search result or a
file opened elsewhere becomes visible:

```dart
var rows = tree.flatten(expansion: const ExpansionState.collapsed());
final target = tree.idOf('/repo/lib/src/tree.dart')!;
rows = rows.reveal(target);
print(rows.map((row) => row.label));
print(rows.indexOfNode(target));
```

```text
(repo, lib, src, tree.dart, main.dart, test, README.md)
3
```

`ExpansionState.reveal(tree, id)` expands every ancestor in a state, for
when you have no rows yet.

### Saving the expansion

Rows carry two states. `expansion` is what the rows show, including the
folders a search opened to reveal its matches. `requestedExpansion` leaves
those out: it is what you passed in, plus every later `expandNode`,
`collapseNode`, `toggleNode`, and `reveal`. Persist `requestedExpansion`, so
clearing the search does not leave every folder it opened expanded:

```dart
final search = tree.flatten(
  expansion: const ExpansionState.collapsed(),
  filter: TreeQuery.parse('tree'),
);
print(search.map((row) => row.label));
print(search.expansion.toJson());

final saved = search.requestedExpansion.toJson();
print(saved);
final restored = ExpansionState.fromJson(saved);
print(tree.flatten(expansion: restored).map((row) => row.label));
```

```text
(repo, lib, src, tree.dart, test, tree_test.dart)
{default: collapsed, exceptions: [/repo, /repo/lib, /repo/lib/src, /repo/test]}
{default: collapsed, exceptions: []}
(repo)
```

The search opened four folders to show its two matches. The saved state
has none of them, so the restored view shows only `repo`, as before the
search. `toJson` returns a map of strings and lists, ready for
`jsonEncode`.

## Search

`TreeQuery.parse` turns the text of a search box into a filter. It never
throws: text it does not understand is searched for literally. A node
matches when it matches every term.

| Term | Matches |
| --- | --- |
| `main` | names that contain `main` (case-insensitive by default) |
| `tree test` | names that contain `tree` and `test` |
| `"my notes"` | names that contain the phrase; quoted text is literal |
| `!test` | nodes that do not match `test`; works with any term |
| `*.dart`, `test_?.md` | whole names that match the glob (`*` any run, `?` one character) |
| `ext:dart`, `ext:dart,md` | files whose name ends with `.dart` (or `.md`) |
| `ext:tar.gz` | files whose name ends with `.tar.gz`; `ext:` is a suffix test |
| `type:file`, `type:dir` | files, or directories (`type:f`, `type:d` also work) |
| `path:lib/src` | nodes whose canonical path contains `lib/src` |
| `lib/src` | the node `src` in a path containing `lib/src`, so what a compacted row shows can be typed |
| `lib/` | the direct children of a folder whose path ends with `lib` |
| `src/*.dart` | nodes whose last path components match the glob |

Plain terms and globs look at the node's name, and terms with a `/` also
look at its path. See `TreeQuery` for the complete rules.

```dart
final project = DirectoryTree.fromPaths([
  '/repo/lib/src/tree.dart',
  '/repo/lib/src/tree.g.dart',
  '/repo/lib/main.dart',
  '/repo/test/tree_test.dart',
  '/repo/docs/my notes.md',
  '/repo/dist/app.tar.gz',
  '/repo/README.md',
]);
List<String> find(String text) {
  final query = TreeQuery.parse(text);
  return project.nodes.where(query.matches).map((n) => n.name).toList();
}

print(find('tree test')); // [tree_test.dart]
print(find('tree !*.g.dart')); // [tree.dart, tree_test.dart]
print(find('"my notes"')); // [my notes.md]
print(find('ext:md')); // [my notes.md, README.md]
print(find('ext:tar.gz')); // [app.tar.gz]
print(find('type:dir path:lib')); // [lib, src]
print(find('lib/')); // [src, main.dart]
print(find('src/*.dart')); // [tree.dart, tree.g.dart]
```

### Highlighting

`matchRanges` returns the parts of a label to highlight, sorted and merged:

```dart
String highlight(String text, TreeQuery query) {
  final buffer = StringBuffer();
  var last = 0;
  for (final range in query.matchRanges(text)) {
    buffer
      ..write(text.substring(last, range.start))
      ..write('[${text.substring(range.start, range.end)}]');
    last = range.end;
  }
  return (buffer..write(text.substring(last))).toString();
}

final query = TreeQuery.parse('tree test');
print(highlight('tree_test.dart', query)); // [tree]_[test].dart
```

Pass it the text the row shows, such as `row.label`. Globs, `key:value`
terms, and negated terms do not highlight.

### Filters

`TreeQuery` is one kind of `TreeFilter`. Build your own with
`TreeFilter.where` and combine filters with `and`, `or`, and `negate`:

```dart
final dartFiles = TreeFilter.where<Object?>(
  (node) => node.isFile && node.path.extension == '.dart',
);
final generated = TreeFilter.where<Object?>(
  (node) => node.name.endsWith('.g.dart'),
);
final filter = dartFiles
    .and(generated.negate())
    .and(TreeQuery.parse('tree'));
print(project.render(filter: filter));
```

```text
repo/
├── lib/
│   └── src/
│       └── tree.dart
└── test/
    └── tree_test.dart
```

A filtered view keeps the matches and the ancestors that lead to them;
`row.isMatch` tells the two apart. `flatten` calls the filter once per node
and never again: incremental updates reuse the results. A filter must
therefore give the same answer for the same node every time. An empty query
(`TreeQuery.parse('')`) reports `matchesAll`, and the view skips filtering.

By default `flatten` expands every ancestor of a match (`expandMatches:
true`), as the search in the previous section showed. With `false`, the
expansion is used as given and matches inside collapsed folders stay
hidden:

```dart
final hidden = tree.flatten(
  expansion: const ExpansionState.collapsed(),
  filter: TreeQuery.parse('ext:md'),
  expandMatches: false,
);
print(hidden.map((row) => row.label)); // (repo)
```

## Selection

`SelectionState` is an immutable set of selected ids with a mode
(`single` or `multiple`) and an anchor for range selection. `select` is a
plain click, `toggle` a ctrl-click, and `extendTo` a shift-click, which
selects everything between the anchor and the clicked row in the order the
user sees:

```dart
final rows = tree.flatten();
var selection = const SelectionState.empty(mode: SelectionMode.multiple);
selection = selection.select(tree.idOf('/repo/lib/main.dart')!);
selection = selection.extendTo(
  tree.idOf('/repo/test/tree_test.dart')!,
  rows.map((row) => row.id),
);
print(selection.selected.map((id) => id.value));
print(selection.anchor!.value);
```

```text
(/repo/lib/main.dart, /repo/test, /repo/test/tree_test.dart)
/repo/lib/main.dart
```

`extendTo` reads the order once and stops at the end of the range, so a
lazy `rows.map(...)` costs no copy. The anchor stays put, so repeated
shift-clicks pivot around it.

### Checkboxes

For checkbox trees, checks are defined over leaves (files and empty
directories). A directory is `CheckState.checked` when every leaf below it
is selected, `unchecked` when none is, and `partial` otherwise:

```dart
var checks = const SelectionState.empty(mode: SelectionMode.multiple);
final lib = tree.idOf('/repo/lib')!;
checks = checks.check(tree, lib);
print(checks.checkStateOf(tree, lib)); // CheckState.checked
print(checks.checkStateOf(tree, tree.roots.single)); // CheckState.partial
print(checks.length); // 2
print(checks.isSelected(lib)); // false

const single = SelectionState.empty();
print(single.canCheck(tree, lib)); // false
print(single.canCheck(tree, tree.idOf('/repo/test')!)); // true

print(SelectionState.fromJson(checks.toJson()) == checks); // true
```

Checking `lib` selected its two files; the directory's own id stays out of
the selection. `checkStates(tree)` returns the state of every node in one
pass, for drawing. In single mode, `check` throws a `StateError` for a
directory with more than one leaf; ask `canCheck` first to enable or
disable the checkbox.
Every operation that changes nothing returns the same object, and
`prune(tree)` drops ids a rebuilt tree no longer has.

## Diffs

### `ListDiff` for animated lists

`ListDiff.compute` compares two keyed lists, such as the rows before and
after a change, and returns the indices to animate:

```dart
final before = tree.flatten();
final after = before.collapseNode(tree.idOf('/repo/lib')!);
final diff = ListDiff.compute(before, after, keyOf: (row) => row.id);
print(diff.removedIndices); // [4, 3, 2]
print(diff.insertedIndices); // []
print(diff.changedIndices); // [1]

final list = [...before];
for (final index in diff.removedIndices) {
  list.removeAt(index);
}
for (final index in diff.insertedIndices) {
  list.insert(index, after[index]);
}
print(list.length); // 5
```

`list` now has the keys of `after`, in the same order.

Apply the removals first, in the order given (descending), then the
insertions in the order given (ascending). That is the protocol of
Flutter's `AnimatedList`: `removeItem(index, ...)` for each removed index,
then `insertItem(index)` for each inserted one. `changedIndices` are items
that kept their place but differ by `==` (here, the `lib` row is no longer
expanded); rebuild those without animating them.

A moved item is one removal plus one insertion. The diff keeps the longest
run of items whose order did not change, so it uses as few removals and
insertions as possible:

```dart
final moves = ListDiff.compute(
  ['a', 'b', 'c', 'd'],
  ['b', 'x', 'a', 'd'],
  keyOf: (item) => item,
);
print(moves); // ListDiff(removed: [2, 0], inserted: [1, 2], changed: [])
```

Keys must be unique within each list. A key that repeats in the part of
the lists that differs always throws an `ArgumentError`; repeats in the
shared start and end are caught only when assertions are enabled (debug
builds and tests), so release builds skip hashing the rows that did not
move.

### `TreeDiff` for rebuilt trees

`TreeDiff.compute` reports the ids added, removed, and changed between two
trees, for example after a rescan:

```dart
final next = tree.rebuild(
  (builder) => builder
    ..addFile('/repo/lib/src/rows.dart')
    ..remove('/repo/test'),
);
print(TreeDiff.compute(tree, next));
```

```text
TreeDiff(added: [/repo/lib/src/rows.dart], removed: [/repo/test, /repo/test/tree_test.dart], changed: [])
```

A node counts as changed when its kind, path spelling, label, entry (path,
kind, or data), or parent differs. Use it to drop cached state for removed
ids and refresh changed ones; for the order of visible rows, use
`ListDiff`.

## Rendering text

`render` prints the visible rows with connector lines. It takes the same
`expansion`, `filter`, `compactFolders`, and `showRoots` arguments as
`flatten`, plus a `TreeStyle`, a `maxDepth`, and a `label` function:

```dart
print(tree.render(style: TreeStyle.ascii, maxDepth: 1));
```

```text
repo/
|-- lib/
|-- test/
`-- README.md
```

```dart
print(
  tree.render(
    style: TreeStyle.indent,
    label: (row) => row.node.isDirectory ? '[${row.label}]' : row.label,
  ),
);
```

```text
[repo]
  [lib]
    [src]
      tree.dart
    main.dart
  [test]
    tree_test.dart
  README.md
```

`TreeStyle.unicode` is the default; build a `TreeStyle` for other
connectors. `maxDepth: 0` prints only the depth-0 rows. By default
directories get a trailing `/`; a custom `label` replaces that.

## Scanning the file system

The core library never imports `dart:io`. To build a tree from a directory
on disk, import the scanner library as well:

```dart
import 'package:directory_tree/io.dart';
```

```dart
final scanner = DirectoryScanner(
  maxDepth: 2,
  skip: (entity) => entity.path.endsWith('build'),
  onError: (error) => print('skipped ${error.path}: ${error.message}'),
);
final scanned = await scanner.scanTree(projectPath);
print(scanned.render(showRoots: false));
```

```text
lib/
├── src/
└── main.dart
README.md
```

`scanTree` returns a `DirectoryTree<FileSystemEntity>` whose single root is
the scanned directory; each node's `data` is its `File`, `Directory`, or
`Link`. `maxDepth: 2` lists two levels below the scanned directory, so
`src` appears without its contents. Hidden entries (names starting with
`.`) are left out unless `includeHidden` is true, `skip` prunes a subtree
without listing it, and links are not followed unless `followLinks` is
true. A directory that cannot be read goes to `onError` and the scan
continues. `scan` and `scanSync` return the entries without building a
tree.

The scanner needs `dart:io`, so it works on the Dart VM, in native
executables, and in Flutter apps on mobile and desktop, but not on the web.
`example/scan_directory.dart` is a small `tree` command built on it.

## Platform support

| Platform | `directory_tree.dart` | `io.dart` |
| --- | --- | --- |
| Dart VM and native executables | yes | yes |
| Flutter on Android, iOS, macOS, Windows, Linux | yes | yes |
| Web: JavaScript (dart2js) | yes | no |
| Web: WebAssembly (dart2wasm) | yes | no |

The test suite runs on the VM, on Node (JavaScript), and as WebAssembly.
Path parsing, ordering, and search give the same results on each.

## Performance

Median times from `benchmark/`, comparing 1.0.0 with 2.0.0 on generated
project-like (`deep`) and flat (`wide`) trees of 100,000 files. Measured on
an Apple M2 Pro with Dart 3.13.5, AOT-compiled:

| Operation | Shape | 1.0.0 (ms) | 2.0.0 (ms) |
| --- | --- | ---: | ---: |
| Build the tree | deep | 2,389 | 373 |
| Build the tree | wide | 1,714 | 312 |
| Flatten, all expanded | deep | 10.44 | 14.03 |
| Flatten, all expanded | wide | 7.62 | 12.72 |
| Collapse a folder (`collapseNode`) | deep | 9.02 | 1.55 |
| Collapse a folder (`collapseNode`) | wide | 7.04 | 2.02 |
| Flatten with a search query | deep | 54.88 | 17.36 |
| Flatten with a search query | wide | 52.80 | 27.84 |
| Diff the rows before and after a collapse | deep | 29.98 | 41.57 |
| Diff the rows before and after a collapse | wide | 23.53 | 45.74 |

1.0.0 has no incremental collapse, so its collapse time is a full flatten.
At this size a single run can include a full garbage collection, which
moves the median. The
[full results](https://github.com/omar-hanafy/directory_tree/blob/main/benchmark/RESULTS.md)
also list the fastest run of each operation and the 10,000 and 1,000,000
file workloads.

## Gotchas and FAQ

### How do I hide the workspace root?

Make it a fixed root and pass `showRoots: false` to `flatten` or `render`,
as in [Compact folders and hidden roots](#compact-folders-and-hidden-roots).
The root's children become the depth-0 rows.

### Why did a folder disappear after I removed a file?

A directory that exists only because a file is below it is inferred, and it
goes away with its last file. Add a directory entry to keep it:

```dart
final docs = DirectoryTree.fromPaths(['/r/docs/a.md', '/r/b.txt']);
final emptied = docs.rebuild((builder) => builder.remove('/r/docs/a.md'));
print(emptied.nodeAt('/r/docs')); // null

final kept = docs.rebuild(
  (builder) => builder
    ..addDirectory('/r/docs')
    ..remove('/r/docs/a.md'),
);
print(kept.nodeAt('/r/docs')); // DirectoryNode(/r/docs, children: 0)
```

### Why are `README.md` and `readme.md` two nodes?

The default `PathPolicy` is case-sensitive, like Linux. Use
`PathPolicy.caseInsensitive` for Windows or macOS-style trees.

### Why does my search not match the label I display?

`TreeQuery` matches the node's name, and its path for `path:` terms and
terms with `/`. A label you build yourself, for example with
`render(label: ...)` or in a widget, is not searched.

### Can I search for `.tar.gz` files?

Yes: `ext:` is a suffix test, so `ext:tar.gz` matches `app.tar.gz`.
`TreePath.extension` returns only the last extension (`.gz`).

### Why is my `TreeDiff` empty after changing the sort order?

`TreeDiff` matches nodes by id and does not report a reordering of
siblings. A depth change on its own is not reported either: depth shifts
come from an ancestor whose parent changed (for example a directory that
stops being top level), and that ancestor is reported as changed. Diff the
rows with `ListDiff` to see order changes:

```dart
const paths = ['/r/b/', '/r/a.txt'];
final byKind = DirectoryTree.fromPaths(paths);
final byName = DirectoryTree.fromPaths(
  paths,
  options: const TreeOptions(order: TreeOrder.alphabetical),
);
print(TreeDiff.compute(byKind, byName).isEmpty); // true
```

### What happens with an id the tree does not have?

Nothing throws. Lookups return `null`, -1, 0, `false`, or an empty result.
Row updates return the same rows, and state operations that take a tree,
such as `SelectionState.check` and `ExpansionState.reveal`, return the same
state:

```dart
const missing = NodeId('/repo/gone');
print(tree[missing]); // null
print(tree.indexOf(missing)); // -1
print(tree.childrenOf(missing).isEmpty); // true
final rows = tree.flatten();
print(identical(rows.toggleNode(missing), rows)); // true
```

## AI coding assistant support

This repository also ships a plugin that teaches coding agents the exact
directory_tree 2.0.0 API, so they stop writing 1.x calls such as
`TreeBuilder` or `ExpansionSet`. It is tooling for your agent, not part of
the Dart package, and it contains instructions only: no hooks, MCP servers,
or network access.

| Skill | What it covers |
| --- | --- |
| `use-directory-tree` | Building, paths and policies, roots, ordering, issues, rows and incremental expansion, search syntax, selection and checkboxes, diffs, rendering, the scanner, and the traps of each |
| `migrate-directory-tree-v1-to-v2` | The 2.0.0 upgrade: `dart fix --apply` for the three renames, then the manual mapping and the behavior checklist |

Claude Code: in a session, run
`/plugin marketplace add omar-hanafy/directory_tree`, then
`/plugin install directory-tree@directory-tree-tools`. From a shell:

```sh
claude plugin marketplace add omar-hanafy/directory_tree
claude plugin install directory-tree@directory-tree-tools
```

Codex:

```sh
codex plugin marketplace add omar-hanafy/directory_tree
codex plugin add directory-tree@directory-tree-tools
```

Antigravity, for the `agy` CLI and the IDE and desktop app, which read the
same plugin folder:

```sh
agy plugin install https://github.com/omar-hanafy/directory_tree/tree/main/tooling/ai/directory-tree
```

Start a new agent session after installing (or run `/reload-plugins` in
Claude Code). The skills load when a request needs them, for example
"upgrade this project to directory_tree 2.0.0" or "add a checkbox tree to
this file picker with directory_tree". The
[plugin README](https://github.com/omar-hanafy/directory_tree/blob/main/tooling/ai/directory-tree/README.md)
covers updating, removing, and the checks behind it. Installation is tested
in Claude Code 2.1.312, Codex 0.165.0, and Antigravity CLI 1.4.9, and CI
repeats the test weekly with each host's current release.

## Migrating from 1.x

2.0.0 is a rewrite; no 1.x API remains. [MIGRATION.md](MIGRATION.md) maps
the old types and calls to the new ones.

## Related

[flutter_directory_tree](https://pub.dev/packages/flutter_directory_tree)
builds Flutter tree view widgets on this package.

## License

MIT. See [LICENSE](LICENSE).
