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
