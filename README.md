# Directory Tree

Deterministic virtual tree builder for Dart and Flutter UIs. The package keeps
track of source paths, selection state, and expansion flags so you can render a
consistent file browser, diff viewer, or project navigator across platforms.

## Why use it?
- maps flat file scans into a stable hierarchical structure
- supports virtual nodes alongside real files
- works with multiple source roots and custom root labels
- canonicalizes Windows and POSIX paths into a single deterministic shape
- deterministic folder IDs (including nested folders) that survive rebuilds for smooth UI updates

## Quick start
Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  directory_tree: ^1.0.0
```

Build a tree:

```dart
final builder = TreeBuilder();
final tree = builder.build(
  entries: [
    const TreeEntry(
      id: 'readme',
      name: 'README.md',
      fullPath: '/repo/README.md',
    ),
  ],
  sourceRoots: const ['/repo'],
);

final repoFolderId = tree.nodes.values
    .firstWhere((n) => n.type == NodeType.folder && n.name == 'repo')
    .id;
final children = tree.nodes[repoFolderId]!.childIds;

// Render from the smart visible root
final startId = tree.visibleRootId;
```

## Flattening & Rendering
To render the tree (e.g., in a `ListView`), convert the graph into a flat list using a `FlattenStrategy`.

```dart
// 1. Define which nodes are expanded
final expandedIds = <String>{tree.rootId, ...}; 

// 2. Flatten the tree
final strategy = const DefaultFlattenStrategy();
final visibleRows = strategy.flatten(
  data: tree, 
  expandedIds: expandedIds,
);

// 3. Render
for (final row in visibleRows) {
  print('${"  " * row.depth} ${row.name}');
}
```

### Efficient Updates
Use `diffVisibleNodes` to compute the minimal changes between two states. This is ideal for Flutter's `AnimatedList`:

```dart
final diff = diffVisibleNodes(oldList, newList);
// diff.removeIndicesDesc -> Remove items
// diff.insertIndicesAsc -> Insert items
```

## Configuration options
`TreeBuilder.build` accepts flags to fine-tune output:
- `expandFoldersByDefault` toggles initial expansion state
- `selectNewFilesByDefault` selects files the first time they appear
- `preferDeepestRoot` breaks ties when multiple source roots match
- `stripPrefixes` normalizes absolute paths into project-relative ones
- `sortChildrenByName` enforces alphabetical folder-then-file ordering
- `autoPickVisibleRoot` hoists away redundant single-folder chains for display
- `visibleRootMaxHoistLevels` limits how far hoisting can travel (default 2)
- `visibleRootIgnoreVirtualFiles` keeps scratch entries from blocking hoists
- `mergeVirtualIntoRealFolders` lets metadata folders reuse matching real directories
- Virtual entries can set `metadata['virtualParent']` (e.g. `notes/daily`) to
  group them inside virtual folders under `/tree` or attach to existing real
  folders (e.g. `repo/notes`)

## Example
Run the console sample in `example/` for a full demonstration:

```sh
cd example
dart pub get
dart run
```

## Development
- `dart format .`
- `dart analyze`
- `dart test`

Pull requests are welcome -- please include tests for new behaviors.
